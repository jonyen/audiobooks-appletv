import { useState } from "react";
import { signInWithGoogle } from "../lib/firebase";

export default function SignIn() {
  const [error, setError] = useState<string | null>(null);

  return (
    <main className="signin">
      <h1>Audiobooks — Read Along</h1>
      <p>Sign in to listen, read along, and keep your progress in sync with Apple TV and the web.</p>
      <button
        onClick={() => {
          setError(null);
          signInWithGoogle().catch((e: Error) => setError(e.message));
        }}
      >
        Sign in with Google
      </button>
      {error && <p className="error">{error}</p>}
    </main>
  );
}
