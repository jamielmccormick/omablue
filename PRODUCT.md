# Product

## Register

product

## Users

OmaBlue is for a technical Omarchy user working at a keyboard with one
user-owned Mac signed into Messages. The user needs to glance at message state
from the Omarchy bar, open a focused messaging panel when needed, and respond
without leaving the desktop or weakening macOS security.

## Product Purpose

OmaBlue provides a private, Omarchy-native Messages experience through a
user-owned Mac. The bar should make iMessage recognizable at a glance, show
unread state, and communicate new-message activity without becoming noisy. The
panel should begin as a privacy-preserving read-only inbox and thread viewer:
message content is hidden until intentional interaction, conversation rows are
scrollable and avatar-led, and group conversations can show participant
avatars or a configured group image. The thread view will later support text
and pasted-image sending with explicit outcome states.

Notifications are user-controlled through Omarchy's notification surfaces.
Syncing and offline states are visible but quiet. OTP recognition and copy to
clipboard are a later convenience feature, not part of the first vertical
slice.

## Brand Personality

Quiet, native, humane. OmaBlue should feel like a thoughtful part of Omarchy,
not a generic chat dashboard or a reproduction of Apple's interface.

## Anti-references

- Generic SaaS dashboards with metric cards and interchangeable admin chrome
- Noisy notification walls with constant flashing, urgency, or badge overload
- Literal iMessage clones that copy Apple's visual language instead of adapting
  the workflow to Omarchy
- Dense terminal interfaces that make keyboard power feel like command-line
  work

## Design Principles

- Reveal on intent: default to privacy, then show content when the user chooses
  a conversation or thread.
- Glanceable first, deep on demand: the bar communicates state quickly; the
  panel provides the full workflow.
- Keyboard-native, mouse-inclusive: every important action has a clear
  keyboard path without making pointer interaction secondary or awkward.
- Quiet signals, redundant meaning: theme-aligned color and motion may enhance
  a state, but text, icons, counts, or structure must carry its meaning too.
- Native boundaries stay visible: sync, offline, permissions, and uncertain
  operations should be understandable without exposing credentials or raw
  transport details.

## Accessibility & Inclusion

The plugin must work with keyboard-only navigation and must not rely on color
alone for unread, new-message, syncing, or offline states. Motion should be
reduced or removed when the available Omarchy/Qt environment indicates that
preference. Text should follow the active Omarchy font and remain usable at
larger sizes and stronger contrast settings. Where the nonstandard desktop
environment cannot expose a platform preference directly, the implementation
must degrade to clear static indicators rather than failing silently.
