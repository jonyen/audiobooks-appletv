import { useState } from "react";
import { signInWithApple } from "../lib/firebase";

export default function SignIn() {
  const [error, setError] = useState<string | null>(null);

  return (
    <main className="signin">
      <h1>Audiobooks — Read Along</h1>
      <p>Sign in to listen, read along, and keep your progress in sync with Apple TV.</p>
      <button
        onClick={() => {
          setError(null);
          signInWithApple().catch((e: Error) => setError(e.message));
        }}
      >
         Sign in with Apple
      </button>
      {error && <p className="error">{error}</p>}
    </main>
  );
}
