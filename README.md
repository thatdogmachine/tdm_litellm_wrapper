# tdm_litellm_wrapper
Convenience wrapper for litellm project, using Nix


## Important

This deployment configuration is deliberately insecure to misuse from local host. Understand those risks before using.


## Motivations

- When running local models, system resources are often at a premium, such that even (e.g.) docker is an undesirable overhead
    - In this case it is desirable to minimize the memory consumed by the proxy and it's dependencies.

- litellm is fast moving software
    - It's useful to be able to target a specific commit / tag of the repo, as well as integrating / testing bespoke / local changes


## Pre-req's


### 1) Local model endpoint(s) and loaded models

Examples include:

[LM Studio](https://lmstudio.ai/) <-- used to test this config

[Ollama](https://ollama.com/)

But this choice and configuration is left as an exercise for the reader.


### 2) nix


#### 2.1) install

A couple of install options exist including:

[NixOS project installer](https://nixos.org/download/) <-- used to test this config

[Determinate Nix](https://docs.determinate.systems/determinate-nix/) <-- preferred by some with an assertion of being more end user friendly


#### 2.2) configuration

[Flakes](https://nixos.wiki/wiki/Flakes) need to be enabled

`~/.config/nix/nix.conf`

with:

```
experimental-features = nix-command flakes
```

Is the approach used to test this config and likely the easiest


## 3) litellm repo cloned locally

```
git clone https://github.com/BerriAI/litellm.git
```


## 4) Configuring Models

You can use whatever LiteLLM config file you wish, but this example uses `proxy_server_config-local-example.yaml`

Follow the existing docs to configure the [model-list](https://docs.litellm.ai/docs/proxy/configs) based on the models you made available in 1) above.

`qwen/qwen3-coder-30b` is provided as an example of a model running on LM Studio.


## 5) Running LiteLLM proxy

```
cd litellm

nix develop --fallback
```

Review briefly the output in the shell, then follow the instructions to `Start the LiteLLM Proxy Server` - noting the config file may be different from what you chose in 4)