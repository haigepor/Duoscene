export function success<T>(data: T, requestId: string) {
  return { data, requestId };
}

export function failure(code: string, message: string, requestId: string) {
  return { error: { code, message }, requestId };
}
