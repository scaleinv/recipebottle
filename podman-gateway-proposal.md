
# Engage Podman for Gateway Feature

## Title

Enable Container to connect as network gateway

## Feature Request Description (NEEDS SVG ATTACH)

I want a container running less trusted code ("BOTTLE") to be able to use a trusted, carefully configured container ("SENTRY") to intermediate all local and internet access.

Find at [RBM System Vision](https://scaleinv.github.io/recipebottle) a diagram and abstract of my passion open-source project that needs this.

Prototypes using podman with bespoke BOTTLE dockerfiles have proven the concept. However, for this project to succeed, it needs to be able to use existing images and/or stock dockerfiles for BOTTLE.

Could podman add a network feature to allow SENTRY to function as gateway to BOTTLE from its earliest DHCP?

## Suggest Potential Solution

Based on my experiments, I propose adding an `--as-gateway` flag to the `podman network connect` command.
This parameterless option would:

1. Assign the gateway IP to the specified container (SENTRY in my case)
2. Handle MAC address consistency to avoid ARP cache issues
3. Ensure proper network initialization during container startup

This simple, unobtrusive feature could enable many security-focused container patterns. A search of your open issues led me only to [DMZ Feature Request](https://github.com/containers/podman/issues/20222) which may be consonant, though idle.

The proposed flag might align well with podman's transition to netavark, potentially making implementation straightforward.

## Alternatives Considered

My road to this feature request has been long. Since I'm not a deep networking expert, I've been freely using Claude from Anthropic and ChatGPT to help me work on this journey from docker to podman.

After finding that docker couldn't connect host and internal networks to the same container, I switched to podman and explored several approaches:

1. **Direct Gateway Assignment:** I first tried the naive approach - simply assigning the gateway IP to the SENTRY container. Podman silently rejected this request.
2. **Network Configuration Deep Dive:** Next came experimentation with --opt and --dns options in podman commands, along with AI-suggested CNI configuration nudges. These didn't just work.
3. **BOTTLE-side Solutions:** Implementing dhclient in BOTTLE showed promise but revealed network race conditions during container startup. Some test BOTTLEs worked, others didn't - and more importantly, this required intimate BOTTLE container startup modifications.
4. **Privileged BOTTLE Container Approach:** Success came with elevating BOTTLE privileges to allow network stack modification, but this violated the core security premise of using SENTRY to protect untrusted BOTTLE containers.  Race condition vulnerabilities here too.
5. **Post-startup SENTRY Reconfiguration:** My latest attempts focused on reassigning SENTRY's IP after startup. This led to fascinating podman machine network namespace investigation with tcpdump, but ultimately failed due to ARP cache complications (AIs themselves uncertain that gratuitous ARP cache poisoning would work).
6. **Future-proofing Investigation:** When ChatGPT suggested deeper focus on CNI customization, I learned podman is transitioning from CNI to netavark. I explored other container runtimes for stable future-proof CNI environments, from locally managed containerd to CRI-O. However, I think people who might want to use my open source starting point will want the full 'desktop' feature set absent from CRI-O and other kubernetes-focused alternatives.

Finally, thank you podman maintainers for an amazing project!
I'm not averse to attempting an implementation PR myself, once we scrub this concept for consonance with your long term visions.
