# ViRest

ViRest is an iOS app that helps young adults discover sports and physical
activities that fit their health condition, preferences, and environment. The
app provides personalized sports recommendations designed to help users safely
improve cardiovascular fitness and maintain or lower their resting heart rate.

## Overview

Many young adults have elevated resting heart rates due to sedentary lifestyles
but lack guidance on how to improve their cardiovascular health through
appropriate exercise.

Most existing fitness apps focus on general fitness goals and provide generic
workout plans rather than targeting improvements in resting heart rate or
cardiovascular efficiency.

ViRest addresses this problem by turning user input, including physical
condition, sports preferences, and environmental factors, into personalized
sports recommendations.

The app is designed primarily for young adults who are unsure which sports are
suitable for them and want to improve their cardiovascular fitness safely.

### Main Goals

- Help users discover sports that fit their physical condition.
- Provide recommendations based on health, environment, and sports preferences.
- Support users in reaching or maintaining a healthy resting heart rate.
- Encourage sustainable cardiovascular fitness through appropriate physical activity.

## Features

### Personalized Sports Recommendation

Generate personalized sports recommendations based on:

- Health and physical condition
- Environmental conditions
- Sports preferences
- Resting heart rate goals

Recommendations are intended to help users choose suitable activities to safely
improve their cardiovascular fitness.

### Apple Health Integration

Integrates with Apple Health through HealthKit to access relevant health data
used by the app.

### Workout Check-In and Feedback

Users can check in after workouts and provide feedback about their exercise
experience. This feedback supports future plan adjustments and
recommendations.

### Authentication

Users can authenticate with:

- Sign in with Apple
- Google Sign-In

Authentication is provided by Firebase Authentication. User profiles, plans,
check-in history, suitability feedback, badges, and titles are stored in Cloud
Firestore.

## Tech Stack

- Swift
- SwiftUI
- SwiftData
- HealthKit
- Firebase Authentication
- Cloud Firestore
- WidgetKit

## Requirements

The project currently targets the following environment:

- iOS 26.0 or later
- Xcode 26.6
- Swift language mode 5.0
- A valid Apple Developer team for HealthKit, App Groups, and Sign in with Apple
- A Firebase project configured for the app bundle identifier

The main app bundle identifier is:

```text
halo-dek.virest
```

The widget bundle identifier is:

```text
halo-dek.virest.widget
```

## Getting Started

### 1. Clone the repository

```bash
git clone git@github-tomo-dev:TomoyaKureno/ViRest.git
cd ViRest
```

If your Git host does not have the `github-tomo-dev` SSH alias, clone using
the HTTPS or SSH URL configured for your account.

### 2. Open the project

Open `ViRest.xcodeproj` in Xcode 26.6. The project uses an Xcode project file,
not a Swift Package Manager executable project.

### 3. Configure Firebase

Create or select a Firebase project and register an iOS app with this exact
bundle identifier:

```text
halo-dek.virest
```

Download the matching `GoogleService-Info.plist` and place it at:

```text
ViRest/GoogleService-Info.plist
```

The file is intentionally ignored by Git. Do not commit API keys or project
configuration belonging to a private Firebase project.

Enable these Firebase Authentication providers:

- Apple
- Google

Create a Cloud Firestore database and publish rules that allow an authenticated
user to access only their own user document and check-in subcollection. The
app uses these paths:

```text
users/{firebaseUserId}
users/{firebaseUserId}/checkIns/{checkInId}
titles/{titleId}
```

The `titles` collection must contain at least one readable title document with
these fields:

```text
name: string
minTotalActionsRequired: number
```

### 4. Configure Apple Developer capabilities

The main app target requires:

- Sign in with Apple
- HealthKit
- App Groups

The shared App Group used by the app and widget is:

```text
group.halo-dek.virest.shared
```

Add the matching capabilities and provisioning profiles to the Apple Developer
App ID and Xcode target before running on a physical device.

### 5. Configure Google Sign-In

Use the `REVERSED_CLIENT_ID` value from the downloaded Firebase plist in
`ViRest/Info.plist` under `CFBundleURLSchemes`. The value must belong to the
same Firebase project as the plist.

### 6. Build and run

Run the `ViRest` scheme on an iOS 26 simulator or device.

Build from the command line:

```bash
xcodebuild -project "ViRest.xcodeproj" \
  -scheme "ViRest" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the complete test suite:

```bash
xcodebuild -project "ViRest.xcodeproj" \
  -scheme "ViRest" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO test
```

## App Flow

- No Firebase session: authentication screen
- Signed-in user without a Firestore `sportPlan`: onboarding
- Signed-in user with a Firestore `sportPlan`: main tabs
- Firestore bootstrap failure: retryable account-load error screen

## Data and Persistence

- Cloud Firestore is the source of truth for signed-in user data, plans, titles, and check-in history.
- SwiftData-backed repositories provide local profile, plan, check-in, badge, and health cache storage.
- Check-in counter updates, plan progress, action totals, and check-in history are written atomically in a Firestore transaction.
- Firestore-specific document types are kept in the data layer and mapped to domain models where applicable.

## Documentation

See [`docs/TECHNICAL_DOCUMENTATION.md`](docs/TECHNICAL_DOCUMENTATION.md) for
the detailed architecture, data model, recommendation rules, and project
notes.
