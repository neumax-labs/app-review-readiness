import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.habitcoach',
  appName: 'Habit Coach',
  webDir: 'dist',
  server: {
    url: 'https://habit-coach.example-host.app',
    cleartext: true,
  },
};

export default config;
