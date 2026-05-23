Captive Portal Recipes

EXPERIMENTAL — AI-Generated — Work in Progress

This project centralizes captive portal login knowledge into a template-based recipe format that compiles to multiple targets, including travelmate .login scripts and standalone shell scripts. It bridges existing solutions such as CaptivePortalAutoLogin and travelmate community scripts into a unified, contributable format.

Quick Start

Compile a recipe to a travelmate .login script:

./compiler/compile-recipe.sh recipes/cisco-meraki.json -o meraki.login

Specify a compilation target:

./compiler/compile-recipe.sh recipes/cisco-meraki.json --target travelmate -o meraki.login

Project Structure

```
captive-portal-recipes/
├── recipes/                   # JSON recipe definitions
├── templates/
│   └── targets/
│       └── travelmate/       # Shell script templates for travelmate
├── compiler/                  # Recipe compiler
├── tools/                     # Capture and import utilities
├── tests/                     # Mock environment and test runner
├── docs/                      # Schema, architecture, compatibility
└── .github/                   # CI configuration
```

Recipe Format

A recipe is a JSON file declaring how to authenticate against a captive portal. The schema defines all supported fields and authentication types. See docs/SCHEMA.md for complete details.

Authentication Types

- click-through-grant: Extract a grant URL from redirect or body, then GET it.
- form-submit: Fetch a form, extract hidden fields, and POST with optional credentials.
- csrf-form-submit: Extract a CSRF token from cookie or body, then POST the form with it.
- json-api: Call JSON endpoints, optionally chaining multiple steps with variable extraction.
- chap-md5: CHAP MD5 challenge-response used by MikroTik routers.
- js-redirect: Extract a JavaScript redirect URL from the page body and follow it.
- multi-step-form: Hotel or retail portals requiring multiple page submissions.
- cookie-chain: PHP session portals that maintain cookies across requests.

Tools

- tools/capture-portal.sh: Semi-automated HAR capture helper for portal flow observation.
- tools/import-cpal.sh: Importer that converts CaptivePortalAutoLogin Kotlin handlers into recipes.

Testing

Run the mock test suite:

cd tests && ./test-recipes.sh

All 44 recipes pass with the mock environment.

Compatibility

See docs/COMPATIBILITY.md for a detailed matrix showing reliability, source attribution, and testing status.

Attribution

See docs/ATTRIBUTION.md for credits to CaptivePortalAutoLogin, travelmate, and other community resources.

Contributing

To add a new recipe:

1. Observe the portal flow (browser DevTools or capture-portal.sh).
2. Write a JSON recipe following the schema.
3. Compile and test using the mock environment.
4. Open a PR with the recipe file and any required template changes.

License

GPL-3.0

This license matches the attribution requirements of CaptivePortalAutoLogin and is compatible with travelmate.

Status

What Works

- 44 recipes covering 8 authentication types.
- 8 shell templates supporting all auth types.
- Recipe compiler generating travelmate .login scripts.
- Mock test suite with 44/44 passing.
- Tools for portal capture and CPAL import.

What Is Planned

- Live device testing on real hardware.
- Additional compilation targets beyond travelmate.
- More recipes derived from the 16 complex CaptivePortalAutoLogin handlers.

What Is Unknown

- Real device testing has not been performed.
- Reliability ratings in COMPATIBILITY.md are aspirational until device-tested.
