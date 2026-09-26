import { supabase } from '../supabase';

export function Login() {
  const google = () => supabase.auth.signInWithOAuth({ provider: 'google' });
  const signup = (email: string, pw: string) => supabase.auth.signUp({ email, password: pw });
  return (
    <div>
      <span className="badge">Beta</span>
      <button onClick={google}>Continue with Google</button>
      <button onClick={() => signup('a', 'b')}>Sign up</button>
    </div>
  );
}
