/*
 * Copyright (c) 2024. Crucible Labs Inc.
 *
 * Crucible is a closed source project developed by Crucible Labs Inc.
 * Do not copy, share distribute or otherwise allow this source file
 * to leave hardware approved by Crucible Labs Inc. unless otherwise
 * approved by Crucible Labs Inc.
 */

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:desktop_webview_auth/desktop_webview_auth.dart';
import 'package:desktop_webview_auth/google.dart';
import 'package:fast_log/fast_log.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluf/service/hive_service.dart';
import 'package:fluf/service/user_service.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:serviced/serviced.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:toxic/extensions/future.dart';
import 'package:universal_io/io.dart';

class LoginService extends StatelessService {
  bool isSignedIn() => FirebaseAuth.instance.currentUser != null;

  Future<void> signOut() => Future.wait(
      [FirebaseAuth.instance.signOut(), GoogleSignIn.standard().signOut()]);

  String? extractFirstName(User user) {
    List<String> dns = getPotentialExtractionNames(user);

    if (dns.isNotEmpty) {
      return dns.first.contains(" ") ? dns.first.split(" ").first : dns.first;
    }

    return null;
  }

  List<String> getPotentialExtractionNames(User user) {
    List<String> dns = user.providerData
        .where((element) => element.displayName != null)
        .map((e) => e.displayName!)
        .toList();
    if (user.displayName != null) {
      dns.add(user.displayName!);
    }

    success(
        "Extracted ${dns.length} display names from user: ${dns.join(",")}");
    return dns;
  }

  String? extractLastName(User user) {
    List<String> dns = getPotentialExtractionNames(user);

    if (dns.isNotEmpty) {
      return dns.first.contains(" ")
          ? dns.first.split(" ").sublist(1).join(" ")
          : dns.first;
    }

    return null;
  }

  Future<UserCredential> signInWithApple() async {
    late UserCredential c;
    final rawNonce = generateNonce();
    final nonce = sha256ofString(rawNonce);
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCredential = OAuthProvider("apple.com").credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    c = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
    Map<String, dynamic> profile = c.additionalUserInfo?.profile ?? {};
    String? firstName = appleCredential.givenName ??
        profile["given_name"] ??
        extractFirstName(c.user!);
    String? lastName = appleCredential.familyName ??
        profile["family_name"] ??
        extractLastName(c.user!);
    verbose("Apple First Name: $firstName");
    verbose("Apple Last Name: $lastName");
    await svc<UserService>().getUserData(c.user!.uid,
        firstName: firstName, lastName: lastName, onSignedUp: (user) {
      info("User Signed Up!");
    });

    if (firstName != null && lastName != null) {
      svc<UserService>().updateName(first: firstName, last: lastName).then(
          (value) =>
              success("Set first and last name to $firstName $lastName!"));
    }
    return c;
  }

  Future<bool> attemptAutoSignIn() async {
    if (!kIsWeb && Platform.isWindows && await hasAuthToken()) {
      verbose("Attempting Auto Sign In with Google on Windows");
      try {
        await signInWithGoogle(retry: false);

        if (isSignedIn()) {
          await svc<UserService>().bind();
          return true;
        } else {
          await clearAuthToken();
        }
      } catch (e, es) {
        error("Failed to auto sign in with Google");
        error(e);
        error(es);
      }
    }

    await clearAuthToken();

    return false;
  }

  Future<void> saveAuthToken(AuthResult r) async {
    await dataBox.put("at", r.accessToken);
    await dataBox.put("it", r.idToken);
    await dataBox.put("ts", r.tokenSecret);
    verbose("Saved Auth Token");
  }

  Future<void> clearAuthToken() async {
    await dataBox.delete("at");
    await dataBox.delete("it");
    await dataBox.delete("ts");
    verbose("Cleared Auth Token");
  }

  Future<bool> hasAuthToken() => Future.value(dataBox.get("at") != null);

  Future<AuthResult> loadAuthToken() => Future.value(AuthResult(
        accessToken: dataBox.get("at"),
        idToken: dataBox.get("it"),
        tokenSecret: dataBox.get("ts"),
      ));

  Future<AuthResult?> openGoogleSignInPopupWindows() =>
      DesktopWebviewAuth.signIn(GoogleSignInArgs(
          clientId:
              '68879956753-33fk62umu8sjn4b66vpkamdpspuq6d7m.apps.googleusercontent.com',
          redirectUri: 'https://crucible-build.firebaseapp.com/__/auth/handler',
          scope: 'email'));

  Future<UserCredential> signInWithGoogleWindows({bool retry = true}) async {
    if (await hasAuthToken()) {
      try {
        verbose("Logging in with GSToken on Windows using saved token");
        final OAuthCredential at = GoogleAuthProvider.credential(
            accessToken: (await loadAuthToken()).accessToken);
        return await FirebaseAuth.instance.signInWithCredential(AuthCredential(
          providerId: at.providerId,
          signInMethod: at.signInMethod,
          accessToken: at.accessToken,
          token: at.token,
        ));
      } catch (e, es) {
        error("Looks like our saved credentials are invalid!");
        warn(e);
        warn(es);
        await clearAuthToken();

        if (retry) {
          return signInWithGoogleWindows();
        } else {
          rethrow;
        }
      }
    } else {
      try {
        verbose("Logging in with GSToken on Windows with popup");
        final AuthResult ar = (await openGoogleSignInPopupWindows())!;
        final OAuthCredential at =
            GoogleAuthProvider.credential(accessToken: ar.accessToken);
        return await FirebaseAuth.instance
            .signInWithCredential(AuthCredential(
              providerId: at.providerId,
              signInMethod: at.signInMethod,
              accessToken: at.accessToken,
              token: at.token,
            ))
            .thenRun((_) => saveAuthToken(ar));
      } catch (e, es) {
        error("Failed to sign in with Google!");
        error(e);
        error(es);
        rethrow;
      }
    }
  }

  Future<UserCredential> signInWithGoogle({bool retry = true}) async {
    late UserCredential c;

    try {
      if (kIsWeb) {
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        c = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else if (Platform.isWindows) {
        verbose("Logging in with GSToken on Windows");
        c = await signInWithGoogleWindows(retry: retry);
      } else {
        GoogleSignInAccount? googleUser =
            await GoogleSignIn.standard().signIn();
        GoogleSignInAuthentication? googleAuth =
            await googleUser?.authentication;

        if (googleAuth == null) {
          error("Google Auth is null!");
        }

        OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth?.accessToken,
          idToken: googleAuth?.idToken,
        );
        c = await FirebaseAuth.instance.signInWithCredential(credential);
      }
      Map<String, dynamic> profile = c.additionalUserInfo?.profile ?? {};
      String? firstName = profile["given_name"] ?? extractFirstName(c.user!);
      String? lastName = profile["family_name"] ?? extractLastName(c.user!);
      //String? profilePictureUrl = profile["picture"];

      verbose("Google First Name: $firstName");
      verbose("Google Last Name: $lastName");
      svc<UserService>().grabName(firstName, lastName);
    } catch (e, es) {
      error("Failed to sign in with Google!");
      error(e);
      error(es);
    }
    return c;
  }

  String generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
