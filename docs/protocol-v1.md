# Relaypad protocol v1

The iPhone sends relative pointer movement, clicks, key transitions, and Unicode text to one Mac. App versions and wire versions are independent. The six-key and seven-key iPhone decks both use v1. A Space bar, for example, uses the existing key transition with Mac virtual key code 49.

## Discovery and authentication

The Mac registers a DNS-SD service of type `_relaypad._tcp` in `local.` on a system-assigned TCP port. The TXT record contains `id`, a persistent UUID string identifying the receiver. The phone displays the advertised service name and indexes its saved pairing code by UUID. Both the service name and UUID are visible during discovery. The Mac listener accepts connections from peers attached to the local link.

The Mac generates a uniformly random 12-character secret from `0123456789ABCDEFGHJKMNPQRSTVWXYZ` using the system random generator. This gives 60 bits of entropy. The printed code groups characters 4–4–4. To normalize input, uppercase it, remove whitespace and hyphens, map O to 0 and I or L to 1, then require exactly 12 characters from the alphabet.

Both endpoints use TLS 1.2 with `TLS_PSK_WITH_AES_128_GCM_SHA256` (0x00A8). Set the PSK identity to the ten UTF-8 bytes of `Relaypad-1`. The shared key is the raw 32-byte result of HMAC-SHA-256 with the normalized code's UTF-8 bytes as its key and the identity bytes as its message. The application checks the negotiated cipher suite before it processes frames.

| Public test vector | Value |
| --- | --- |
| Normalized test code | `0123456789AB` |
| PSK identity, hex | `52 65 6c 61 79 70 61 64 2d 31` |
| PSK, hex | `541e42996a91c56157049ba1e8da4f725ee71ddbfa5f235a9fe9a01f1dbd4fc2` |

Anyone on the local link who knows the current code can authenticate. The code is a reusable shared credential. **New code** on the Mac replaces it and closes existing connections. The phone and Mac save pairing secrets in their Keychains. A Mac that cannot initially save its code can still use it for the current run. The phone remembers the last successfully saved receiver for foreground reconnection. **Disconnect** clears that automatic selection. **Forget saved code** removes the selected phone-side credential.

## Framing

After the TLS handshake, each message consists of a four-byte unsigned, big-endian payload length followed by that many bytes of UTF-8 JSON. The length excludes the prefix. Valid lengths are 1 through 100,000 bytes inclusive. Read the stream in order. A read can contain part of a frame or several complete frames. Object member order and whitespace have no semantic meaning.

For example, a heartbeat consists of `00 00 00 10` followed by the 16 bytes of `{"heartbeat":{}}`. Every message and event has one case name. The literal field `_0` wraps an unnamed value in the v1 encoding and must be preserved.

## Session

| Direction | Payload example | Behavior |
| --- | --- | --- |
| Phone → Mac | `{"hello":{"version":1,"name":"iPhone"}}` | Send immediately after TLS is ready. Only version 1 is accepted. The name is a display label. |
| Mac → phone | `{"ready":{"canControl":true}}` | Admits the session. A false value means pairing succeeded and Mac Accessibility permission is needed before sending input. The Mac sends another ready message when permission changes. |
| Mac → phone | `{"busy":{}}` | Another session is active. The Mac sends this reply and closes the candidate connection. The phone retries a known receiver with backoff. |
| Phone → Mac | `{"input":{"_0":{"key":{"code":18,"down":true}}}}` | Dispatch one input event on the active session. |
| Either | `{"heartbeat":{}}` | Maintains liveness on an admitted session. The apps send heartbeats every 3 seconds and check for more than 10 seconds without a decoded inbound message on each tick. |

The Mac admits one phone at a time, applies events in order, and checks its local Accessibility permission before injecting input. A malformed frame, unsupported version, unexpected message, or invalid input ends the connection. On stop, disconnect, timeout, or loss of permission, the receiver releases the remote keys and mouse buttons it owns. Each new session starts with a fresh hello and ready exchange. V1 has no replay queue, input acknowledgement, or feature-negotiation exchange.

## Input events

Wrap one of the following objects in `{"input":{"_0":EVENT}}`. Button names are the strings `left`, `right`, and `middle`.

| Event object | Meaning and limits |
| --- | --- |
| `{"move":{"dx":-1.5,"dy":3}}` | Relative movement in Mac display coordinates. Positive x moves right and positive y moves down. Both numbers must be finite and each magnitude may be at most 65,536. |
| `{"scroll":{"dx":8,"dy":-2}}` | Pixel scroll deltas. The Mac maps dy to the vertical wheel and dx to the horizontal wheel. The same numeric limits apply. |
| `{"button":{"button":"left","down":true}}` | Change the held state of a mouse button. Use down, move, up to drag. |
| `{"click":{"button":"right","count":1}}` | Click the named button at the current pointer position. Count is 1 or 2. |
| `{"key":{"code":63,"down":false}}` | Press or release a Mac virtual key. Codes are integers 0–127 inclusive. For chords, press modifiers first and release in reverse order. Fn is 63, Control is 59 and Option is 58. |
| `{"text":{"_0":"Hello 👋"}}` | Insert Unicode text into the focused app, up to 16,384 UTF-8 bytes before JSON escaping. |
| `{"releaseAll":{}}` | Release every held button and key belonging to this session. |

## Independent release compatibility

- An iPhone or Mac update claiming v1 support must interoperate with the messages and limits above. Keep the Bonjour type, PSK derivation, cipher, framing, case names, `_0` wrappers, required fields and input semantics stable.
- UI, shortcut presets and receiver behavior can evolve independently while they use existing events. A new default key requires no receiver update if that virtual key already fits the protocol.
- Compatible optional metadata may be added inside an existing payload only when a v1 peer can ignore it and newer peers continue to accept archived payloads without it. An unknown message or event case ends a v1 session. New senders must use v1 cases throughout a v1 session.
- An incompatible protocol needs an explicit new selection mechanism, such as a separate discovery service for v2 alongside v1. The shipped v1 hello selects a single version and closes on a mismatch. Document the minimum peer protocol in the release notes of any build that retires v1.

Run `checks/protocol-v1.sh` on a Mac before releasing either endpoint. The test decodes fixed earlier v1 payloads, compares current serializer output, and exchanges framed messages over loopback TLS with an independently keyed test peer. The lifecycle lives in [PhoneLink](../Phone/PhoneLink.swift) and [MacLink](../Mac/MacLink.swift). The shared implementation is in [RemoteProtocol](../Shared/RemoteProtocol.swift) and [SecureChannel](../Shared/SecureChannel.swift).
