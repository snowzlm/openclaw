# Optional plugin delivery containment

Base: `v2026.11.5-beta.1` (`bc061f935bfd79ad09e3e98c6df9f2e8f1e28bea`).

An unredeemable turn capability previously threw while constructing optional plugin
message delivery, before unrelated plugin tools could initialize. The fix omits
that optional delivery without minting authority or relaxing identity validation.
Existing send-time revocation, registry replacement, ordinary authorized delivery,
and scheduled/delivery-only exclusions remain covered by the existing suite.

The seven added cases exercise the production plugin tool resolver with an
unknown, revoked, expired, or agent/run/session-key/session-id mismatched token.
They assert plugin resolution continues while no delivery authority is exposed.
The existing fixture is reused; no new Gateway boot, real timer, or network call.
The test-line allocation covers this distinct fail-closed initialization contract.

The manual `admission-lifecycle-investigation.yml` workflow runs the new cases
against the immutable release source (expected seven product assertion failures),
then runs the entire affected file on the patched source. Its first commit must
be directly parented by the pinned release. No automatic push test is added.
Cloud results and timings are pending until that workflow completes.

This contains initialization failure; it does not establish why a production turn
token became unredeemable. It is not a production incident reproduction or a live
installation patch. No service, credentials, persisted state, or message transport
is modified. Activation requires a separately supported supervised deployment.
