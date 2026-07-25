# AGENTS.md

## Project Overview

Build a Flutter mobile application for university students to order food from the campus cafeteria.

The purpose of the application is to:

* Reduce cafeteria queues.
* Allow students to see available meals before arriving.
* Allow students to place food orders in advance.
* Help cafeteria staff manage orders efficiently.
* Minimize food waste caused by abandoned orders.

This application will eventually use Firebase for authentication and data storage, but Firebase must not be implemented until its phase is activated.

---

# Product Vision

The completed system may include:

Student Features

* Registration
* Login
* Browse daily menu
* Categories
* Place orders
* View order history
* Account management

Cafe Admin Features

* Registration
* Login
* Add food items
* Edit food items
* Remove food items
* Manage orders
* Mark orders as collected

Order Management

* Order status tracking
* Collection confirmation
* Prevention of abandoned orders

Backend

* Firebase Authentication
* Cloud Firestore
* Firebase Storage
* firebase notifications

These features are future phases and must not be implemented unless activated.

---

# Application Navigation

Bottom Navigation Bar must contain:

1. Home
2. Categories
3. Search
3. Orders
4. Account

This navigation structure should remain consistent throughout development.

---

# Agent Development Rules

## Rule 1

Implement only the active phase.

Do not implement future phases.

All changes made are must be **production ready** hence solve any security and performance issues arise during development.

---

## Rule 2

Before writing code, answer:

1. Current phase?
2. Requirement being implemented?
3. Files being modified?
4. Possible regressions?

Then proceed.

---

## Rule 3

Use simple Flutter architecture.

Preferred structure:

lib/
├── data/
├── screens/
├── widgets/
├── models/
├── services/
├── navigation/
├── repositories/

Avoid unnecessary complexity.

Do not introduce advanced architecture unless requested.

---

## Rule 4

Preserve working functionality.

Never rewrite entire screens when small modifications are sufficient.

---

## Rule 5

After completing a feature:

* Verify build succeeds.
* Verify navigation works.
* Verify all features still work.

---

# Current Phase

PHASE 9

# TASK

Implement secure Email Verification and Forgot Password functionality for CampusBite.

The implementation must be production-ready.

The implementation must prioritize security over convenience.

Do NOT redesign the authentication system.

Do NOT replace Firebase Authentication.

Reuse the existing authentication flow.

---

# CURRENT SYSTEM

Already implemented:

✓ Firebase Authentication

✓ Student Registration

✓ Student Login

✓ Firestore Users Collection

Reuse the existing code.

---

# OBJECTIVE

Implement:

1. Email Verification

2. Forgot Password

using Firebase Authentication.

Do NOT implement custom OTP verification.

Do NOT build a custom email service.

Use Firebase's built-in secure email verification and password reset mechanisms.

---

# EMAIL VERIFICATION FLOW

Registration

↓

Firebase creates account

↓

Firebase sends verification email

↓

User opens email

↓

User clicks verification link

↓

Returns to app

↓

User taps "I've Verified My Email"

↓

Reload Firebase user

↓

If verified

↓

Create Firestore user profile (if not already created)

↓

Enter application

---

# REGISTRATION

After successful account creation:

Immediately send verification email.

Use:

sendEmailVerification()

Never skip this step.

---

# FIRESTORE PROFILE CREATION

Do NOT create the Firestore user profile before email verification.

Only create:

users/{uid}

after

emailVerified == true

This prevents unused and fake accounts from polluting Firestore.

---

# VERIFY EMAIL SCREEN

Create:

VerifyEmailScreen

Display:

• Verification instructions

• Registered email address

Buttons:

I've Verified My Email

Resend Verification Email

Change Email

Logout

Do not automatically proceed without user confirmation.

---

# VERIFICATION CHECK

When the user taps:

I've Verified My Email

Execute:

Reload Firebase user.

Check:

currentUser.emailVerified

If:

false

Show:

"Your email has not been verified yet."

Remain on VerifyEmailScreen.

If:

true

Create Firestore profile (if missing).

Navigate to Home.

---

# RESEND EMAIL

Allow users to resend verification email.

Implement cooldown.

Cooldown:

60 seconds.

Disable the resend button during cooldown.

Prevent spam.

---

# CHANGE EMAIL

Allow the user to cancel registration.

Delete the unverified Firebase account if appropriate.

Return to RegisterScreen.

The user may register again with a corrected email.

---

# LOGIN FLOW

When a user logs in:

Immediately reload Firebase user.

Check:

emailVerified

If verified:

Continue normally.

If not verified:

Do NOT allow access to the application.

Redirect to VerifyEmailScreen.

Never allow unverified users to place orders.

Never allow unverified users to access protected features.

---

# FORGOT PASSWORD

Create:

ForgotPasswordScreen

Fields:

Student Email

Buttons:

Send Reset Email

Back to Login

---

# EMAIL VALIDATION

Accept only:

Emails which are in correct email formats.

Validate email format before calling Firebase.

---

# PASSWORD RESET

Use Firebase Authentication only.

Call:

sendPasswordResetEmail()

Do not implement custom reset codes.

Do not store reset tokens.

Do not store temporary passwords.

---

# PASSWORD RESET RESPONSE

Always display the same success message.

Example:

"If an account exists for this email, a password reset email has been sent."

Never reveal whether the account exists.

Prevent account enumeration attacks.

---

# PASSWORD POLICY

Minimum length:

8 characters

Require:

Uppercase

Lowercase

Number

Special character

Validate before registration.

Display clear validation messages.

---

# FIRESTORE SECURITY

Never trust Firestore fields for verification status.

Never create:

verified = true

inside Firestore.

Always trust:

Firebase Authentication

emailVerified

only.

---

# SECURITY RULES

Protect application features using:

request.auth != null

Where email verification is required, rely on the Firebase Authentication verified email state rather than client-side checks.

Do not rely solely on Flutter UI restrictions.

---

# RATE LIMITING

Verification resend:

One email every 60 seconds.

Password reset:

Prevent repeated rapid requests from the client.

Do not automatically retry failed requests.

---

# SESSION HANDLING

When email becomes verified:

Reload Firebase user.

Refresh authentication state.

Do not require the user to restart the application.

---

# ERROR HANDLING

Handle:

Network unavailable

Too many requests

Invalid email

User disabled

Expired session

Firebase exceptions

Display user-friendly messages.

Never expose internal Firebase error codes.

---

# USER EXPERIENCE

Show progress indicators during:

Registration

Verification

Password reset

Verification reload

Disable buttons while requests are running.

Prevent duplicate requests.

---

# ACCESS CONTROL

Until email verification completes:

User cannot:

Place orders

Modify profile

Use cart synchronization

Receive order notifications

Access account features

Only VerifyEmailScreen is accessible.

---

# CODE STRUCTURE

By following the app UI colour and theme Create:

verify_email_screen.dart

email_verification_service.dart

Reuse:

reset_password.dart

Authentication repository

Do not duplicate authentication logic.

---

# CODE QUALITY

Separate:

UI

Business logic

Firebase service

Repository

Use clean architecture principles.

Avoid duplicated code.

---

# TESTING

Verify:

✓ Registration sends verification email.

✓ Verification email link works.

✓ User cannot enter app before verification.

✓ Verified user enters app.

✓ Firestore profile created only after verification.

✓ Verification resend cooldown works.

✓ Change email flow works.

✓ Logout works from VerifyEmailScreen.

✓ Forgot Password sends reset email.

✓ Password reset works.

✓ Same response shown for existing and non-existing emails.

✓ Network failures handled.

✓ Firebase exceptions handled.

✓ Existing login unaffected.

✓ Existing registration unaffected.

✓ Existing Firestore security unaffected.

✓ Existing notifications unaffected.

✓ Existing order system unaffected.

---

# DELIVERABLES

Provide:

1. Files created.

2. Files modified.

3. Email Verification implementation.

4. Forgot Password implementation.

5. Updated authentication flow.

6. Testing checklist.

Stop after completing this phase.

Do NOT implement custom OTP emails.

Do NOT implement SMS verification.

Do NOT implement multi-factor authentication.

Maintain full backward compatibility with the existing authentication system.

---

# Phase Completion Criteria

Phase 9 is complete when:

* the new features works well with past features.
* App runs successfully.
* No runtime errors occur.
