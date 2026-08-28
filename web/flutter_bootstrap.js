// Bootstrap personnalisé : identique à celui généré par défaut par
// Flutter, sauf qu'il n'enregistre PAS le service worker interne de
// Flutter (flutter_service_worker.js, déprécié, utilisé pour le cache
// hors-ligne des assets — on n'en a pas besoin). Ce service worker
// entrait en conflit avec celui de Firebase Cloud Messaging
// (firebase-messaging-sw.js) : les deux couvrent le même "scope"
// (même dossier), et l'enregistrement/mise à jour permanente de celui
// de Flutter empêchait celui de Firebase de rester stable et actif
// ("AbortError: Subscription failed - no active Service Worker").
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({});
