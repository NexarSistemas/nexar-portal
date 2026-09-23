export const QR_CODE_PATTERN = /^[A-Za-z0-9_-]{32}$/;

export function normalizeQrCode(value) {
  const code = String(value ?? '').trim();
  return QR_CODE_PATTERN.test(code) ? code : null;
}

export function qrCodeFromLocation(location) {
  const url = new URL(location.href);
  const queryCode = normalizeQrCode(url.searchParams.get('qr') ?? url.searchParams.get('code'));
  if (queryCode) return queryCode;
  const match = url.pathname.match(/\/q\/([A-Za-z0-9_-]{32})\/?$/);
  return normalizeQrCode(match?.[1]);
}

export function normalizeRpcRow(data) {
  if (Array.isArray(data)) return data[0] ?? null;
  return data && typeof data === 'object' ? data : null;
}

export function normalizeClientAccounts(rows) {
  if (!Array.isArray(rows)) return [];
  return rows.flatMap((account) => {
    const tenant = Array.isArray(account.tenant) ? account.tenant[0] : account.tenant;
    if (!account?.id || !account?.tenant_id || !tenant?.activo || !tenant?.nombre) return [];
    return [{
      id: account.id,
      tenantId: account.tenant_id,
      tenantName: tenant.nombre,
    }];
  });
}

export function calculateBalance(movements) {
  return (Array.isArray(movements) ? movements : []).reduce((total, movement) => {
    const points = Number(movement?.puntos);
    return Number.isFinite(points) ? total + points : total;
  }, 0);
}

export function isExpired(operation, now = new Date()) {
  return Boolean(operation?.expires_at && new Date(operation.expires_at) <= now);
}

export function pendingRedeems(operations, now = new Date()) {
  return (Array.isArray(operations) ? operations : []).filter((operation) => (
    operation?.tipo === 'redeem'
    && ['pending_customer', 'pending_staff'].includes(operation.estado)
    && !isExpired(operation, now)
  ));
}

export function clientOperationText(operation) {
  if (operation?.tipo !== 'redeem') return '';
  if (operation.estado === 'pending_customer') return 'Escaneá el QR del comercio para continuar.';
  if (operation.estado === 'pending_staff') return 'El comercio debe confirmar el canje.';
  return '';
}

export function createAttemptStore(createKey) {
  const attempts = new Map();
  return {
    get(signature) {
      if (!attempts.has(signature)) attempts.set(signature, createKey());
      return attempts.get(signature);
    },
    clear(signature) { attempts.delete(signature); },
    clearAll() { attempts.clear(); },
  };
}
