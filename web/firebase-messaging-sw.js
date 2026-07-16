// Copyright 2026 davidkivuyo, johnsonmushi, edwinkessy276-art, jugraki-art.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Service worker required by Firebase Cloud Messaging on the web.
// This file is loaded by Firebase's SDK to handle background push messages.
// More info: https://firebase.google.com/docs/cloud-messaging/js/receive

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAvFaZE8wKzOPNQDxtGAJhi476KEyXrTTs',
  appId: '1:902096299828:web:5a94bab6f2f1f2ea656761',
  messagingSenderId: '902096299828',
  projectId: 'foodorder-8ffcf',
  authDomain: 'foodorder-8ffcf.firebaseapp.com',
  storageBucket: 'foodorder-8ffcf.firebasestorage.app',
  measurementId: 'G-6307HPK7ZN',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Background message received: ', payload);

  const notificationTitle = payload.notification?.title ?? 'Campus Bite';
  const notificationOptions = {
    body: payload.notification?.body ?? '',
    icon: '/icons/Icon-192.png',
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
