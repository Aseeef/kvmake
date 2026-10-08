# kvmake

Edit KubeVirt on your laptop. Build and test on a remote VM.

KubeVirt builds are heavy: Bazel, containers, and often nested VMs for functional tests. Running that stack on a laptop burns battery, saturates CPU and disk, and can require a fat network path for registries and deps leaving little resources for your browser or your zoom client. **kvmake** keeps your editor and checkout local, then rsyncs the tree to a builder, runs `make` there, and syncs results back.

## Why remote builds

- **Faster iteration** — Point builds at a machine with more CPU, RAM, and disk so compile, test, and generate finish sooner than on a thermally throttled laptop.
- **Battery and heat** — Leave the compiler farm plugged in; keep the machine you work on cool and usable.
- **Lower bandwidth from where you sit** — Source sync stays between you and the builder; image pulls, caches, and kubevirtci traffic stay on the VM’s network.
- **Work from anywhere** — Coffee shop, travel, or a thin client: same workflow as long as you can reach the builder over SSH.

## How it works

From a KubeVirt checkout:

```bash
kvmake test
kvmake generate
kvmake push
kvmake manifests
```

Each run:

1. rsyncs the tree to the VM  
2. runs `make` with your arguments over SSH  
3. terminal output over SSH and rsyncs generated sources back  

Configure the builder once:

```bash
# ~/.config/kvmake.conf
KVMAKE_HOST=user@builder.example
KVMAKE_REMOTE_DIR='~/kubevirt'
```

Put `kvmake` on your `PATH`, then use it anywhere you’d use `make` inside a KubeVirt tree. Full options, sync rules, and caveats: `kvmake -h`.
