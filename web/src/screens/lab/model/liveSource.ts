export const looksOffline = (error: string | undefined): boolean => {
  if (!error) return false;
  const text = error.toLowerCase();
  return (
    text.includes("failed to fetch") ||
    text.includes("networkerror") ||
    text.includes("load failed") ||
    text.includes("<!doctype")
  );
};
