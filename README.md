# tdm_litellm_wrapper

Convenience wrapper for [LiteLLM](https://docs.litellm.ai/) project, using [Nix](https://nix.dev/index.html)


## Important

This deployment configuration is deliberately INSECURE to misuse from your local network (Proxy reachable with default keys, Postgres unsecured)
 and local host (eg Redis unsecured). Understand those risks before using.
 In particular, ensure you understand how Authorization, not just Authentication, works for
 [passthrough](https://docs.litellm.ai/docs/pass_through/intro) endpoints.


## Motivations

- When running local models, system resources are often at a premium, such that even (e.g.) docker is an undesirable overhead
    - In this case it is desirable to minimize the memory consumed by the proxy and it's dependencies.

- litellm is fast moving software
    - It's useful to be able to target a specific commit / tag of the repo, as well as integrating / testing bespoke / local changes


## Versioning

See git tags or where they exist, Github releases. HEAD of main doesn't have automated tests, and is the development branch.


## Pre-req's


### 1) Endpoint(s) and models

For local models, options include:

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

`bedrock/converse/qwen.qwen3-next-80b-a3b` is provided as an example of a AWS Bedrock cloud model using aws access & secret keys, in this case `os.environ/aws_access_key_id` & `os.environ/aws_secret_access_key`


Remote models implies api keys. An example `.env` file:
```
# lines start with spaces because zsh will omit those from history if pasted
 export aws_access_key_id=<your-key>
 export aws_secret_access_key=<your-key>
 export GEMINI_API_KEY=<your-key>
```


### 5) Configuring Budgets / Usage reporting

The UI for this requires `master_key` be set. This example uses the example [master_key](https://docs.litellm.ai/docs/proxy/config_settings#:~:text=Doc%20Secret%20Managers-,master_key,-string) supplied in LiteLLM docs & examples.

This key needs to be passed by your Agent / Client. An example for gemini-cli / llxprt-code is provided later in this doc.


### 6) Configuring LiteLLM location & version

See `litellmVersion` and `litellmPath` in `flake.nix`.

These need to be set appropriately for your needs. Specifically, the `litellmPath` assumes the LiteLLM repo is 'next to' this `tdm_litellm_wrapper` repo.


## Running LiteLLM proxy

```
./rn.sh
```

Review briefly the output in the shell, then:

```
./rp.sh
```

Remember: the config file may be different from what you chose in 4) - if so, adapt the script accordingly.


## Configuring your team / user via UI

The `master_key` may not interact with cost control how you expect, so to mitigate that we'll create a team with a budget, associate a user with that team, and create a virtual key for the user:

- Create a team: http://localhost:4000/ui/?login=success&page=teams
    - Remember to set a max budget
    - Set that budget really low until you satisfy yourself it will block requests
- Create a user: http://localhost:4000/ui/?login=success&page=users
    - Remember to add the user to the team created previously to inherit the budget constraint
- Create a Virtual Key: http://localhost:4000/ui/?login=success&page=api-keys
    - Make sure you are logged in as the `admin` user or you may not see the necessary options


## Configuring your Agent / Client

Example `profile` configuration for `gemini-cli` and `llxprt-code`

Notice: you'll need to specify an auth-key matching what you configured previously in LiteLLM

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

This is only needed if you are modifying the LiteLLM UI, otherwise can be skipped

Run:

```
cd ~/repos/litellm/ui/litellm-dashboard && nix-shell -p nodejs_20 \
    --command "cd ~/repos/litellm/ui/litellm-dashboard && npm run build && \
    destination_dir="../../litellm/proxy/_experimental/out" && \
    rm -rf "$destination_dir"/* && \
    cp -r ./out/* "$destination_dir" && \
    rm -rf ./out"
```
Then restart the proxy.

(Based on `build_ui.sh`)


## upstream changes not yet confirmed or submitted

If functionality doesn't work on a fresh clone of litellm, below may need to be applied.

These are not yet confirmed to be necessary.

boto3 = {version = "1.41.3", optional = true}
