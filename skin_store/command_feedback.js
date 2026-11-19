// The HTTP response accepts the operation. Only a receipt can confirm the outcome.
async function watchDesktopCommand(id, getStatus, onUnknown) {
  const started = performance.now();
  let uncertain = false;
  while (performance.now() - started < 145000) {
    let receipt;
    try {
      const response = await getStatus(`/api/commands/${encodeURIComponent(id)}`, AbortSignal.timeout(2000));
      receipt = response.receipt;
    } catch (_error) {
      // Status retrieval is retryable. The operation may already have finished.
    }
    if (receipt && !receipt.outcome_unknown && ["succeeded", "failed", "expired"].includes(receipt.status)) {
      return receipt;
    }
    if (!uncertain && (receipt?.outcome_unknown || performance.now() - started >= 6500)) {
      uncertain = true;
      onUnknown();
    }
    await new Promise((resolve) => setTimeout(resolve, uncertain ? 2000 : 250));
  }
  return null;
}
