export const STAFF_ROLES = new Set(['admin', 'operador']);

export class UnauthorizedStaffError extends Error {
  constructor() {
    super('Tu cuenta no tiene acceso habilitado a Nexar Fidelización.');
    this.name = 'UnauthorizedStaffError';
  }
}

export function normalizeEmail(value) {
  return String(value ?? '').trim().toLowerCase();
}

export function parseStaffAccess(rows) {
  if (!Array.isArray(rows) || rows.length !== 1) throw new UnauthorizedStaffError();
  const membership = rows[0];
  const tenant = Array.isArray(membership.tenant) ? membership.tenant[0] : membership.tenant;
  if (!STAFF_ROLES.has(membership.rol) || !tenant?.activo || !tenant.nombre) {
    throw new UnauthorizedStaffError();
  }
  return { role: membership.rol, tenantName: tenant.nombre };
}

export function createActionLock() {
  let busy = false;
  return {
    get busy() { return busy; },
    async run(action) {
      if (busy) return { ignored: true };
      busy = true;
      try {
        return await action();
      } finally {
        busy = false;
      }
    },
  };
}

export function operationPresentation(operation, now = new Date()) {
  const expired = operation.expires_at && new Date(operation.expires_at) <= now;
  if (expired) return { label: 'Acción no permitida', tone: 'muted', actions: [] };
  if (operation.tipo === 'redeem' && operation.estado === 'pending_staff') {
    return { label: 'Pendiente de confirmación', tone: 'warning', actions: ['confirm', 'cancel'] };
  }
  if (operation.tipo === 'redeem' && operation.estado === 'pending_customer') {
    return { label: 'Esperando al cliente', tone: 'info', actions: [] };
  }
  if (operation.tipo === 'earn' && operation.estado === 'pending_customer') {
    return { label: 'Esperando confirmación del cliente', tone: 'info', actions: [] };
  }
  return { label: 'Acción no permitida', tone: 'muted', actions: [] };
}

export function panelStateText(state) {
  const texts = {
    loading: 'Cargando información…',
    empty: 'Todavía no hay operaciones pendientes para esta cuenta.',
    error: 'No pudimos completar la acción. Intentá nuevamente.',
    unauthorized: 'Tu cuenta no tiene acceso habilitado a Nexar Fidelización.',
  };
  return texts[state] ?? '';
}
