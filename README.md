# recipemuster
_Wrangling Dubious Containers for Fun and Profit_

I love containers.
Or, I hate containers...
Bottom line, containers are an amazing tool for controlling tool contexts into the ridiculous long term.
Why use python virtual environments when a container can do the same things at whole-server scale?
As an embedded dev, I can't afford to marry python or any other simple package universe for that matter.

It has never been so easy to use so much code that we might not ought to trust.
When the kids say 'just use latest', its great until it isn't, and by then it could be too late.
One bad choice could lead to complete exfiltration of our nascent implementations.

Can we lower the risk to one-person shops and small teams with a few deft tools?

I've been working a while in a branch of a branch to bring some base concepts to life, to build out a container containment bottle concept that grafts into our workflow transparently via git subtrees.
It is feeling so right that I'm going to try and give it healthy enough boundaries for others use.

Alas `docker` networking seems not powerful enough for interweaving host networks and guarded private networks, so this is generally a `podman` undertaking.

More later I trust.

Make Great Things!