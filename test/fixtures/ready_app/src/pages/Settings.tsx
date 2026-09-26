import { Capacitor } from '@capacitor/core';
import { useNavigate } from 'react-router-dom';
import { supabase } from '../supabase';

// Team plans used to say "coming soon" here; the button was removed.
export function Settings() {
  const navigate = useNavigate();
  const deleteAccount = () => supabase.functions.invoke('delete-account');
  const isWeb = !Capacitor.isNativePlatform();
  return (
    <div>
      <button onClick={() => navigate('/paywall')}>Upgrade</button>
      {isWeb && <a href="https://billing.stripe.com/p/login/abc">Manage billing</a>}
      <button onClick={deleteAccount}>Delete account</button>
    </div>
  );
}
