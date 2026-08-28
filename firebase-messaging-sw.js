// Service worker requis par firebase_messaging pour recevoir les
// notifications quand l'onglet du site n'est pas au premier plan.
// Doit être servi à la racine du site (à côté d'index.html).
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDdF4ipuM92GN1GWio_FebRVgV5wR-i0wo',
  authDomain: 'le-pacte-e6c17.firebaseapp.com',
  projectId: 'le-pacte-e6c17',
  storageBucket: 'le-pacte-e6c17.firebasestorage.app',
  messagingSenderId: '409929231979',
  appId: '1:409929231979:web:379d26caf7a29d25e68b2e',
});

firebase.messaging();
