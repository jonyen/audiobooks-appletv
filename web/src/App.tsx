import SignIn from "./components/SignIn";
import { useUser } from "./lib/firebase";

export default function App() {
  const user = useUser();
  if (user === undefined) return null; // auth state still loading
  if (user === null) return <SignIn />;
  return <main>Signed in as {user.displayName ?? user.uid}</main>;
}
