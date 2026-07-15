## File Acronym Mappings — RBK Subdirectory (`Tools/rbk/`)

- **RBA**  → `rbk/rba_auth.sh` (Auth — RBRA/RBRO credential load and role token mint; homes the sitting lifecycle: avow's reuse-path runway gate (BUBC_band_runway, required-runway parameter seam defaulting to the kindled ~2h floor) and the force-fresh renewal verb `rba_novate`. Thin CLI partner `rba_cli.sh` surfaces the sitting-lifecycle tabtargets: novate (`rbw-aN`, mutates) and the read-only cache-alone probe espy (`rbw-as` — verdict + runway via the `<foedus>.sitting` fact, the theurge gate arc's fail-fast branch point))
- **RBDC** → `rbk/rbdc_derived.sh`
- **RBDG** → `diagrams/rbdg*` (Recipe Bottle Diagram family — committed PlantUML `.puml` sources plus rendered light/dark `.svg` pairs, authored for theme-aware `<picture>` embedding. Container: `rbdg` HAS children, names no file. Members: `rbdgl_` federation-login, `rbdgs_` federation-setup, `rbdgm_` federation-seam. Light SVGs are rendered by the pluml crucible case `rbtdrc_pluml_render_diagrams`; the `*-dark.svg` siblings are produced in the same case by the pure `zrbtdrc_darken_svg` recolor — no second container trip. The diagram set lives in the case's `diagrams/*.puml` glob alone: a new diagram is just a `rbdgX_*.puml` dropped in `diagrams/`, rendered in both modes on the next pluml fixture run.)
- **RBF**  → Foundry prefix (non-terminal: children rbfb, rbfc, rbfd, rbfh, rbfk, rbfl, rbfr, rbfv). The former `rbf_Foundry.sh` monolith was decomposed and its residual renamed to `rbfd_director.sh`; no file is named bare `rbf_`.
- **RBFB** → `rbk/rbfb_beckon.sh` (Foundry Beckon — the per-fact "next tabtargets" signpost: after a chain HEAD writes a fact, the emitter for that fact announces the tabtargets that consume it. Guard-free, composes the BUK `buc_tabtarget` primitive. One emitter per fact type; today only `rbfb_beckon_hallmark` (the RBF_FACT_HALLMARK consumer roster — summon/plumb/rekon readers + anoint/drive writers). Sourced by the producing HEADs rbfd ordain + rbfk kludge.)
- **RBFC** → `rbk/rbfc*` (Foundry Core family — Container (terminal: names no file). The `rbfc_FoundryCore.sh` monolith was decomposed into the children below; the rbfc CLI is now the 0-top `rbfc0_cli.sh`.)
  - **RBFCV** → `rbk/rbfcv_*.sh` (Foundry Core vessel-resolution)
  - **RBFCB** → `rbk/rbfcb_*.sh` (Foundry Core build-host primitives — wait-build-completion, git-metadata, write-script-body, native-path; relocated verbatim from the former `rbfc` monolith and sourced by the rbfc 0-trick entry `rbfc0_core` so every consumer reaches them unchanged; also sourced directly by the `rblds_` spine and the Rust fast-path driver.)
  - **RBFCA** → `rbk/rbfca_*.sh` (Foundry Core step-assembly)
  - **RBFCG** → `rbk/rbfcg_*.sh` (Foundry Core GAR-REST)
  - **RBFCP** → `rbk/rbfcp_*.sh` (Foundry Core plumb — ~640 lines, the single biggest extraction)
  - **RBFC0** → `rbk/rbfc0_core.sh` (Foundry Core 0-trick entry — the module gestalt: single inclusion-guard + kindle + leaked tool-image globals `z_rbfc_tool_*` (copied verbatim). CLI partner `rbfc0_cli.sh` (`zrbfc_furnish`); bare `rbfc_cli.sh` is retired so `rbfc` names no file now that it has children.)
- **RBFD** → `rbk/rbfd_director.sh` (Foundry Director Build — Director-side Cloud Build orchestration: `rbfd_ordain`/`rbfd_build`/`rbfd_mirror`/`rbfd_graft`, plus reliquary/quota/registry preflights and `zrbfd_stitch_build_json`; CLI partner `rbfd_cli.sh`)
- **RBFH** → `rbk/rbfh_hygiene.sh` (Foundry Hygiene — Dockerfile FROM-line constraint shared by kludge and conjure; thin CLI partner `rbk/rbfh_cli.sh` surfaces the contract via `rbw-fhc`/`rbw-fhv`)
- **RBFK** → `rbk/rbfk_kludge.sh` (Foundry Kludge — local vessel image build for development (`rbfk_kludge`); CLI partner `rbfk_cli.sh`, colophon `rbw-fk`)
- **RBFL** → `rbk/rbfl*` (Foundry Ledger family — Container (terminal: names no file). The `rbfl_FoundryLedger.sh` monolith was decomposed into the children below; the rbfl CLI is now the 0-top `rbfl0_cli.sh`. Cluster boundaries — which function lands in which file — were settled at the explosion.)
  - **RBFLY** → `rbk/rbfly_*.sh` (Foundry Ledger yoke — reliquary-touchmark yoke into vessel regimes)
  - **RBFLA** → `rbk/rbfla_anoint.sh` (Foundry Ledger anoint — rewrites RBRV_GRAFT_IMAGE in one graft vessel from the chained build facts; a durable-config chain LINK)
  - **RBFLF** → `rbk/rbflf_feoff.sh` (Foundry Ledger feoff — elects one conjure vessel's base anchor (RBRV_IMAGE_n_ANCHOR) from a bole Lode touchmark express-or-chain, extracted out of conjure so conjure stays a pure chain head; a durable-config chain LINK, colophon `rbw-rvf`. Sibling of anoint/yoke on the durable-config surface — depth-1 relay-then-read, bole-kind gate via the touchmark prefix decoder, buc_reject BUBC_band_chain on broken chain / non-bole)
  - **RBFLD** → `rbk/rbfld_*.sh` (Foundry Ledger delete — reliquary / ledger removal gesture)
  - **RBFLN** → `rbk/rbfln_*.sh` (Foundry Ledger inventory — ledger listing / enumeration gesture)
  - **RBFLW** → `rbk/rbflw_*.sh` (Foundry Ledger wrest — image wrest from registry)
  - **RBFL0** → `rbk/rbfl0_ledger.sh` (Foundry Ledger 0-trick entry — the module gestalt: single inclusion-guard + kindle/sentinel. CLI partner `rbfl0_cli.sh` (`zrbfl_furnish`); bare `rbfl_cli.sh` is retired so `rbfl` names no file now that it has children.)
- **RBFR** → `rbk/rbfr_retriever.sh` (Foundry Retriever — retriever-credentialed hallmark summon (`rbfr_summon`); CLI partner `rbfr_cli.sh`)
- **RBFV** → `rbk/rbfv_verify.sh` (Foundry Verify — hallmark provenance verification: `rbfv_vouch`/`rbfv_about`/`rbfv_vouch_gate`/`rbfv_batch_vouch`; CLI partner `rbfv_cli.sh`)
- **RBGA** → `rbk/rbga_registry.sh`
- **RBGB** → `rbk/rbgb_buckets.sh`
- **RBGC** → `rbk/rbgc_constants.sh`
- **RBGE** → `rbk/rbge_rest.sh` (Google REST — LRO polling + API-enable patterns over rbuh)
- **RBGFT** → `rbk/rbgft_terrier.sh` (Federation Terrier — the muniment access data layer: the three atomic sub-ops `rbgft_engross` / `rbgft_expunge` / `rbgft_peruse` plus the manor-wide read `rbgft_peruse_manor`. Composed by the `rbgp_` polity verbs. Caller-authenticates (token-first). Muniment wire keys under the `rbgft_` sprue.)
- **RBGG** → `rbk/rbgg_governor.sh`
- **RBGI** → `rbk/rbgi_iam.sh`
- **RBGO** → `rbk/rbgo_oauth.sh` (also owns the stateless `rbgo_curl_status_is_transient_predicate` transient-curl-exit classifier)
- **RBGP** → `rbk/rbgp_payor.sh` (Payor — also homes the polity admission verbs `rbgp_brevet` / `rbgp_unseat` / `rbgp_attaint` / `rbgp_rehearse` over token-agnostic `zrbgp_*_core` helpers, dispatched via `rbgp_cli` and wielded as a donned governor mantle (`rba_avow` then `rba_don_capture governor`); colophons `rbw-pB`/`rbw-pU`/`rbw-pA`/`rbw-pr`. Plus the payor-wielded founding verb `rbgp_gird` (colophon `rbw-mG`) seating the first governor — the one admission outside governor wielding.)
- **RBGV** → `rbk/rbgv_probe.sh` (Google Verification — JWT SA and Payor OAuth access probes)
- **RBGW** → `rbk/rbgw_capabilities.sh` (Capability-Sets — shared single home for the three per-role resource-grant lists (governor/director/retriever), applied identically to bridge-legacy enrobed SAs and to the mantle SAs at depot levy; library module, no CLI, sourced by rbgg_cli + rbgp_cli)
- **RBGJS** → `rbk/rbgjs/` (shared cloud-step snippet library — the no-family member of the `rbgj«family»/` cloud-step scheme, where each letter is a family of in-pool step scripts (`rbgja` about, `rbgjb` build, `rbgjl` lode, `rbgjm` mirror, `rbgjr` reliquary, `rbgjv` verify). A *shared* snippet belongs to no single family, so `s` breaks the scheme as the no-family family. Holds composed-once fragments spliced into a step at `#@rbgjs_include «name»` markers by the host-side expander `zrbfc_expand_includes` (`rbfcb_host.sh`). Container: `rbgjs` HAS children (the snippet files), names no bare file.)
- **RBH0** → `rbk/rbh0/` (Handbook directory — decomposed one-function-per-file)
  - `rbh*` is the Handbook family (human-facing procedures), parallel to `rbg*` (Google machinery). Two live groups: `RBHO` onboarding, `RBHP` payor. Colophon pattern: `rbw-o` (onboarding entry) + `rbw-O*` (onboarding tracks) for RBHO; RBHP's guided procedures ride the Guide group as `rbw-gP*`.
  - **RBHO0** → `rbk/rbh0/rbho0_*.sh` (Onboarding 0-prefix — CLI `rbho0_cli.sh` (thin furnish, probe-only deps) + 0-trick gestalt entry `rbho0_onboarding.sh` (kindle, sentinel, probes, shared helpers))
  - **RBHP0** → `rbk/rbh0/rbhp0_*.sh` (Payor 0-prefix — CLI `rbhp0_cli.sh` (full regime + OAuth + IAM deps) + 0-trick gestalt entry `rbhp0_payor.sh` (kindle, sentinel, enforce))
- **RBID** → `rbmm_moorings/rbmv_vessels/common-ifrit-context/` (Ifrit — in-bottle attack binary for crucible testing; shared source across tether/airgap variants)
- **RBJ**  → Jailer prefix (non-terminal: children rbjs, rbjp, rbje, rbjh)
- **RBJS** → `rbmm_moorings/rbmv_vessels/common-sentry-context/rbjs_sentry.sh` (Jailer Sentry - container security setup: iptables, dnsmasq, enclave network; ships in the sentry vessel build context, not Tools/rbk/)
- **RBLD** → `rbk/rbld*` (Lode capture family — fetched-side universal capture; cloud-side in-pool steps in `rbgjl/`; GAR namespace `rbi_ld`; colophon family `rbw-l*`. Container: `rbld` names no file. The former `rbld_Lode.sh` monolith is decomposed into the children below — CLI `rbld0_cli`, 0-trick entry `rbld0_lode`, lifecycle `rbldl_`, capture-assembly spine `rblds_`, delete `rbldd_`, and the per-kind bodies `rbldb_`/`rbldr_`/`rbldw_`/`rbldv_`.)
  - **RBLD0** → `rbk/rbld0_*.sh` (Lode `0`-prefix — CLI `rbld0_cli.sh` (multifacet dispatch across the rbld children) + 0-trick gestalt entry `rbld0_lode.sh`.)
  - **RBLDS** → `rbk/rblds_spine.sh` (Lode capture-assembly spine — the data-driven Cloud Build composer shared by every Lode capture kind.)
  - **RBLDB** → `rbk/rbldb_*.sh` (Bole body — base-kind ensconce, rides the spine.)
  - **RBLDL** → `rbk/rbldl_*.sh` (Lode lifecycle REST — `divine`/`banish`, direct GAR-REST host ops, distinct from the assembly spine.)
  - **RBLDR** → `rbk/rbldr_reliquary.sh` (Reliquary body — `conclave`, the build-tool date-cohort capture kind riding the spine)
  - **RBLDW** → `rbk/rbldw_underpin.sh` (Wsl body — `underpin`, the vendor WSL rootfs capture kind riding the spine)
  - **RBLDV** → `rbk/rbldv_immure.sh` (Podvm body — `immure`, the podman-machine disk capture kind riding the spine)
  - Reserved (legend only, no file — future Lode kind, letter matching the Lode GAR kind-letters): **RBLDT** tool
- **RBLM** → `rbk/rblm*` (Lifecycle Marshal — release-only verbs; the whole `rbw-M*` colophon family is withheld from delivery. CLI partner `rblm_cli.sh`: zero regime to blank template (`rbw-MZ`), lustrate the release clone (`rbw-ML`), feign a station on the probe branch (`rbw-MF`), expede the delivery candidate (`rbw-ME`). Marshal zero takes the intended tree's basename as a required argument and refuses a mismatch against `git rev-parse --show-toplevel` — it blanks the regime of whatever tree it runs in, so that tree must be *named*, never assumed; the refusal fires before the confirmation prompt, so it holds under `BURE_CONFIRM=skip`. Library `rblm_lustrate.sh` homes the **proscription** — the one table judging every enrolled regime field *site-scoped* (this station's cloud and federated identity) or *common*, plus the hardpoint constants no enrollment roll reaches — and the two transforms it drives. Each site row carries two values: the *sterile* one lustration writes, and the *feigned* one feigning writes. Marshal zero and lustration are deliberately distinct: zero mints the gauntlet's entry state against the operator's live payor, so it must leave payor identity standing; lustration runs only in the release clone and erases it. Feigning is lustration's inverse and runs only on the ceremony's throwaway probe branch: a lustrated tree is correctly sterile and therefore cannot *validate*, so feigning invents a false station — visibly false values, never borrowed from a live one — letting the candidate run the consumer's own reveille from the consumer's seat. The proof of erasure is the `damnatio` theurge fixture, which reads this same proscription rather than carrying a second copy — and which reddens on every feigned field, so a probe branch can never be mistaken for a candidate.)
- **RBNNH** → `rbnnh_` prefix family — optional per-nameplate customization files in `rbmm_moorings/{moniker}/`: `rbnnh_compose.yml` (Compose overlay fragment) and `rbnnh_post_charge.sh` (post-charge hook script).
- **RBOB** → `rbk/rbob_bottle.sh`
- **RBOF** → `rbk/rbof_foedus.sh` (Foedus cardinality verbs — the rbw-j colophon family's switch-and-check toothings over the moorings foedera library on a STANDING foedus, never founding/dissolving (that stays the Manor verbs affiance/jilt). `rbof_descry` (rbw-jd, read-only) reads a named foedus's workforce-pool health; `rbof_instate` (rbw-jI) re-points RBRR_ACTIVE_FOEDUS. CLI partner `rbof_cli.sh`. Composed by the `foedus-reuse` theurge fixture.)
- **RBPC** → `rbk/rbpc_constants.sh` (Proving Constants — freehold test-rig constants, segregated from RBCC by operator ruling. Homes the single durable freehold subject (the operator's standing Entra oid — the citizen-definition layer of the identity-layers model: PERMANENT, pool-independent, vs the EVOLVING foedus/depot instances in rbrf.env/rbrd.env). Projects to RBTDGC_FREEHOLD_* as the third peer emit source in rbz_emit_consts, after the colophons and rbcc_emit_consts.)
- **RBYC** → `rbk/rbyc_common.sh` (Common vocabulary — linked term constants for handbook yelp fragments)
- **RBQ**  → `rbk/rbq_qualify.sh` (Qualification orchestrator - tabtarget/colophon/nameplate health)
- **RBTD** → `rbk/rbtd/` (Theurge — crucible test orchestrator)
- **RBTW** → `rbk/rbtd/rbtw_workbench.sh` (Theurge workbench — build/test routing, orthogonal from VOW)
- **RBUH** → `rbk/rbuh_http.sh` (Utility HTTP — JSON REST, polling, shared temp-file machinery)

## Moorings Filesystem Family (`rbm*_`)

RBK-owned directory namespace for the consumer-config moorings tree (`rbmm_moorings/`) — distinct from the `Tools/rbk/` code files above. Branches of the `rbm` prefix (terminal-exclusivity: `rbm` HAS children, never names a thing):

- **`rbmm_`** → moorings umbrella — the directory itself (`rbmm_moorings/`)
- **`rbml_`** → moorings launchers — shared directory holding every kit's `launcher.{wb}_workbench.sh`
- **`rbmn_`** → moorings nodes — remote BURN node profiles
- **`rbmu_`** → moorings users — remote BURP user profiles
- **`rbmv_`** → moorings vessels — vessel build contexts
- **`rbmf_`** → moorings foedera — the foedus library: one `rbef_`-sprued subdirectory per standing foedus (`rbmf_foedera/rbef_entrada/rbrf.env`), the active one selected by `RBRR_ACTIVE_FOEDUS`. The federation regime is stored once here, no copied active file; the accessor resolves the active foedus's `rbrf.env` from the `RBRR_ACTIVE_FOEDUS` selector via `rbcc_rbrf_file_capture`.

Tabtargets dispatch through `tt/z-launcher.sh`, naming their launcher in the `BURD_LAUNCHER` config line as a bare `launcher.<id>_workbench.sh` basename that the trampoline resolves directly under `rbml_launchers/`. This entry is the directory allocation record only.
