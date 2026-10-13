// Public, browser-safe settings. The anon key is designed to be public;
// data is protected by Row Level Security (see /sql). NEVER put a
// service_role key in this repo.
export const CONFIG = {
  supabaseUrl: 'https://tlvnolvfrujhlrffdmeb.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRsdm5vbHZmcnVqaGxyZmZkbWViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxMDk2NTcsImV4cCI6MjEwNTY4NTY1N30.DZNqaSBGb2-Y6w3mcLSVZ98W0jQxohBgbUls0AqoHfE',
  siteUrl: 'https://hltechhub.github.io/Marsellaconecta/',
  contactEmail: 'info@hl-techhub.com',
  // Public VAPID key for Web Push (the private key is an Edge Function secret).
  vapidPublicKey: 'BE050g6DLdrcEqjsSqPfLWzB7seV8eN_OP9YeDXLXUPbWz1eicR6f_A__jNDu7xyV4LaeM8nungqj0PU86c27Yw',
  country: 'El Salvador',
};
