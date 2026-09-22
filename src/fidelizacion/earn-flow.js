export function createEarnAttemptStore(createKey) {
  let attempt = null;
  return {
    get(signature) {
      if (!attempt || attempt.signature !== signature) {
        attempt = { signature, key: createKey() };
      }
      return attempt;
    },
    clear() { attempt = null; },
  };
}

export async function runSuccessfulRefresh({ refresh, onSuccess }) {
  const result = await refresh();
  onSuccess();
  return result;
}

export async function runEarnCreation({ create, refresh }) {
  try {
    await create();
  } catch (error) {
    return { created: false, error };
  }

  try {
    await refresh();
    return { created: true, refreshed: true };
  } catch (error) {
    return { created: true, refreshed: false, error };
  }
}

export function earnFlowNotice(result) {
  if (result.created && result.refreshed) {
    return { type: 'success', message: 'Acreditación creada. Está pendiente de confirmación del cliente.' };
  }
  if (result.created) {
    return {
      type: 'success',
      message: 'La acreditación fue creada, pero no se pudo actualizar la vista. Podés actualizarla sin volver a crearla.',
    };
  }
  return { type: 'error', message: result.error.message };
}
