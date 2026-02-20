const DEFAULT_KEY = "grind-n-chill.web.v1";

export class LocalStorageAdapter {
  constructor(key = DEFAULT_KEY) {
    this.key = key;
  }

  async read() {
    try {
      const raw = localStorage.getItem(this.key);
      if (!raw) {
        return null;
      }
      return JSON.parse(raw);
    } catch (error) {
      console.error("Failed to read app state from localStorage", error);
      return null;
    }
  }

  async write(state) {
    try {
      localStorage.setItem(this.key, JSON.stringify(state));
      return true;
    } catch (error) {
      console.error("Failed to write app state to localStorage", error);
      return false;
    }
  }

  async clear() {
    localStorage.removeItem(this.key);
  }
}

// Future extension point:
// Keep this same API for a cloud adapter (Supabase/Firebase/etc):
//   read() -> state
//   write(state) -> persisted
//   clear() -> reset
