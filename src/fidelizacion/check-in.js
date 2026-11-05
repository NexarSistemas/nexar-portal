export async function loadCheckIns(client, listCheckIns, listCustomers, now = Date.now()) {
  const rows = await listCheckIns(client);
  const unique = [...new Map(rows.filter(row => Date.parse(row.expires_at) > now).map(row => [row.account_id, row])).values()];
  const accounts = [];
  for (let index = 0; index < unique.length; index += 4) {
    const batch = await Promise.all(unique.slice(index, index + 4).map(async row => {
      const [account] = await listCustomers(client, '', 0, 1, row.account_id);
      return account ? { ...row, cliente_email: account.cliente_email } : null;
    }));
    accounts.push(...batch.filter(Boolean));
  }
  return accounts;
}

export function startCheckInPolling(windowTarget, documentTarget, refresh) {
  let timer;
  const update = () => { if (!documentTarget.hidden) void refresh(); };
  const start = () => {
    if (timer !== undefined) return;
    update();
    timer = windowTarget.setInterval(update, 30000);
  };
  const stop = () => {
    if (timer === undefined) return;
    windowTarget.clearInterval(timer);
    timer = undefined;
  };
  windowTarget.addEventListener('pagehide', stop);
  windowTarget.addEventListener('pageshow', start);
  documentTarget.addEventListener('visibilitychange', update);
  start();
}
