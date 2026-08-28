const lienTelechargementApp = 'https://kevinarner.github.io/le_pacte/';

// Projet Supabase du Pacte. L'URL et la clé "anon public" sont faites
// pour être visibles côté client — l'accès aux données est contrôlé
// par les règles RLS définies côté base de données, pas par le secret
// de ces valeurs.
const supabaseUrl = 'https://ssciqjpaibdorvnkkhsk.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNzY2lxanBhaWJkb3J2bmtraHNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc0MjUyOTEsImV4cCI6MjEwMzAwMTI5MX0.9LjNBwizEopgqMvPbScG8YetBFkVrnYk_zKII4BXJ98';

// Clé publique VAPID du projet Firebase (Cloud Messaging > Certificats Web
// Push), nécessaire pour obtenir un token FCM depuis le web. Ce n'est pas
// un secret : elle est faite pour être connue du navigateur client.
const firebaseVapidKey =
    'BLgUsm9qbd-htUKnFUj5ikjmZreLRBvZTwzfL1MZ9t9z4XW0YLi15eT6hx6FhknxVes0DfACcLhMi9VaEwfYjNM';
