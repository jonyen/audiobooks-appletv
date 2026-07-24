import { HashRouter, Route, Routes } from "react-router-dom";
import BookDetail from "./components/BookDetail";
import Home from "./components/Home";
import Player from "./components/Player";
import Search from "./components/Search";
import SignIn from "./components/SignIn";
import { useUser } from "./lib/firebase";
import { usePreambles, useProgress } from "./lib/progress";

export default function App() {
  const user = useUser();
  if (user === undefined) return null;
  if (user === null) return <SignIn />;
  return <SignedInApp uid={user.uid} />;
}

function SignedInApp({ uid }: { uid: string }) {
  const progress = useProgress(uid);
  const preambles = usePreambles(uid);
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<Home progress={progress} />} />
        <Route path="/search" element={<Search progress={progress} />} />
        <Route path="/book/:id" element={<BookDetail progress={progress} />} />
        <Route
          path="/book/:id/play/:section"
          element={<Player progress={progress} preambles={preambles} />}
        />
      </Routes>
    </HashRouter>
  );
}
