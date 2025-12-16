# tdm_litellm_wrapper

Convenience wrapper for [LiteLLM](https://docs.litellm.ai/) project, using [Nix](https://nix.dev/index.html)


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

[NixOS Foundation installer](https://nixos.org/download/) <-- used to test this config

[Determinate Nix](https://docs.determinate.systems/determinate-nix/) <-- preferred by some with a claim of being more end user friendly


#### 2.2) configuration

[Flakes](https://nixos.wiki/wiki/Flakes) need to be enabled

`~/.config/nix/nix.conf`

with:

```
experimental-features = nix-command flakes
```

Is the approach used to test this config and likely the easiest


### 3) LiteLLM repo cloned locally

```
git clone https://github.com/BerriAI/litellm.git
```


### 4) Configuring Models

You can use whatever LiteLLM config file you wish, but this example uses `proxy_server_config-local-example.yaml`

Follow the existing docs to configure the [model-list](https://docs.litellm.ai/docs/proxy/configs) based on the models you made available in 1) above.

`qwen/qwen3-coder-30b` is provided as an example of a local model running on LM Studio.

`gemini/gemini-2.5-flash` is provided as an example of a cloud model that needs an API key, in this case `os.environ/GOOGLE_API_KEY` to be set before running litellm


### 5) Configuring Budgets / Usage reporting

The UI for this requires `master_key` be set. This example uses the example [master_key](https://docs.litellm.ai/docs/proxy/config_settings#:~:text=Doc%20Secret%20Managers-,master_key,-string) supplied in LiteLLM docs & examples.

This key needs to be passed my your Agent / Client. An example for gemini-cli / llxprt-code is provided later in this doc.


### 6) Configuring LiteLLM location & version

See `litellmVersion` and `litellmPath` in `flake.nix`.

These need to be set appropriately for your needs. Specifically, the `litellmPath` assumes the LiteLLM repo is 'next to' this `tdm_litellm_wrapper` repo.


## Running LiteLLM proxy

```
export GOOGLE_API_KEY=<your-key>
export <other-keys-based-on-your-models>=<the-key>
cd litellm

nix develop --fallback
```

Review briefly the output in the shell, then follow the instructions to `Start the LiteLLM Proxy Server` - noting the config file may be different from what you chose in 4)

## Configuring your team / user via UI

The `master_key` may not interact with cost control how you expect, so to mitigate that we'll create a team with a budget, associate a user with that team, and create a virtual key for the user:

- Create a team: http://localhost:4000/ui/?login=success&page=teams
    - Remember to set a max budget
    - Set that budget really low until you satisfy yourself it will block requests
- Create a user: http://localhost:4000/ui/?login=success&page=users
- Create a Virtual Key: http://localhost:4000/ui/?login=success&page=api-keys
    - Make sure you are logged in as the `admin` user or you won't see the necessary options


## Configuring your Agent / Client

Example `profile` configuration for `gemini-cli` and `llxprt-code`

Notice: you'll need to specify an auth-key matching what you configured previosuly in LiteLLM

```
{
    "version": 1,
    "provider": "openai",
    "model": "gemini-2.5-flash", 
    "modelParams": {},
    "ephemeralSettings": {
    "auth-key": "<YOUR-VIRTUAL-KEY-HERE>",
    "base-url": "http://localhost:4000/v1",
    "context-limit": 1000000,
    "disabled-tools": [
        "google_web_search"
    ],
    "max-prompt-tokens": 1000000
    }
}
```


## Rebuilding the UI

Run:

```
cd ~/repos/litellm/ui/litellm-dashboard && nix-shell -p nodejs_20 --command "cd ~/repos/litellm/ui/litellm-dashboard && npm run build && \
    destination_dir="../../litellm/proxy/_experimental/out" && \
    rm -rf "$destination_dir"/* && \
    cp -r ./out/* "$destination_dir" && \
    rm -rf ./out"
```
Then restart the proxy.

Based on `build_ui.sh`


curl 'http://0.0.0.0:4000/key/generate' \
--header 'Authorization: Bearer sk-1234' \
--header 'Content-Type: application/json' \
--data-raw '{"metadata": {"user": "hello@thatdogmachine.com"}}'