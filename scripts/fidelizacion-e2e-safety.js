import { isIP } from 'node:net';

const missingMessage = 'Falta configuración E2E obligatoria.';
const destinationMessage = 'Destino E2E no permitido: se requiere Supabase local en el puerto 54321.';

const keyMessage = 'La clave pública E2E no tiene un formato permitido.';

// Solo inspecciona el formato: no verifica la firma ni los permisos efectivos.
export function validatePublicKey(key, adminKeys = []) {
  if (typeof key !== 'string' || !key || key !== key.trim() ||
      adminKeys.some((admin) => typeof admin === 'string' && admin.length > 0 && admin === key)) {
    throw new Error(keyMessage);
  }
  if (/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(key)) return;
  if (key.startsWith('sb_secret_')) throw new Error(keyMessage);
  const parts = key.split('.');
  if (parts.length !== 3 || parts.some((part) => !/^[A-Za-z0-9_-]+$/.test(part))) {
    throw new Error(keyMessage);
  }
  try {
    const decode = (part) => {
      const bytes = Buffer.from(part, 'base64url');
      if (bytes.toString('base64url') !== part) throw new Error();
      return JSON.parse(bytes.toString('utf8'));
    };
    const header = decode(parts[0]);
    const payload = decode(parts[1]);
    const signature = Buffer.from(parts[2], 'base64url');
    if (!header || typeof header !== 'object' || Array.isArray(header) ||
        typeof header.alg !== 'string' || header.alg.toLowerCase() === 'none' ||
        !payload || typeof payload !== 'object' || Array.isArray(payload) || payload.role !== 'anon' ||
        !signature.length || signature.toString('base64url') !== parts[2]) throw new Error();
  } catch {
    throw new Error(keyMessage);
  }
}
export function validateConfiguration(env, required) {
  if (required.some((name) => !env[name]?.trim())) throw new Error(missingMessage);
  validatePublicKey(env.E2E_FIDELIZACION_ANON_KEY, [
    env.SUPABASE_SERVICE_ROLE_KEY, env.SUPABASE_SECRET_KEY, env.E2E_FIDELIZACION_SERVICE_ROLE_KEY,
  ]);
  return localUrl(env.E2E_FIDELIZACION_URL, true);
}

export function localUrl(value, base = false) {
  const raw = String(value);
  if (!/^http:\/\/(?:localhost|127\.0\.0\.1|\[::1\]):54321(?:[\/?#]|$)/i.test(raw)) {
    throw new Error(destinationMessage);
  }
  let url;
  try { url = new URL(raw); } catch { throw new Error(destinationMessage); }
  if (url.protocol !== 'http:' || url.username || url.password || url.port !== '54321' ||
      !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) ||
      (base && (url.pathname !== '/' || url.search || url.hash))) {
    throw new Error(destinationMessage);
  }
  // Evita que una entrada hosts o DNS redirija localhost a una dirección remota.
  if (url.hostname === 'localhost') url.hostname = '127.0.0.1';
  if (url.hostname !== '[::1]' && isIP(url.hostname) !== 4) throw new Error(destinationMessage);
  return url;
}

export function guardedFetch(baseUrl, fetchImpl = globalThis.fetch) {
  const origin = localUrl(baseUrl, true).origin;
  return async (input, init = {}) => {
    const target = localUrl(input instanceof Request ? input.url : input);
    if (target.origin !== origin) throw new Error(destinationMessage);
    const request = input instanceof Request ? new Request(target, input) : target;
    let response;
    try {
      response = await fetchImpl(request, { ...init, redirect: 'manual' });
    } catch {
      throw new Error('Falló la solicitud E2E local.');
    }
    if (response.status >= 300 && response.status < 400) {
      throw new Error('Redirección E2E rechazada.');
    }
    return response;
  };
}
