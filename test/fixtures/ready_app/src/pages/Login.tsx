import { SignInWithApple } from '@capacitor-community/apple-sign-in';
import { supabase } from '../supabase';

export function Login() {
  const google = () => supabase.auth.signInWithOAuth({ provider: 'google' });
  const apple = async () => {
    const r = await SignInWithApple.authorize({ clientId: 'x', redirectURI: 'y', scopes: 'email' });
    return supabase.auth.signInWithIdToken({ provider: 'apple', token: r.response.identityToken });
  };
  return (
    <div>
      <input placeholder="Your company name" />
      <button onClick={apple}>Continue with Apple</button>
      <button onClick={google}>Continue with Google</button>
      <a href="/privacy">Privacy Policy</a>
    </div>
  );
}
