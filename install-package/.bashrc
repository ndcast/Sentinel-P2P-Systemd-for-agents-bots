# ~/.bashrc - Sentinel dVPN + general aliases

# ---------------- Sentinel dVPN Aliases ----------------
alias keys="sentinel-dvpncli keys list --keyring.backend test --home ~/sentinel-dvpncli"
alias keys-add="sentinel-dvpncli keys add mydvpn --keyring.backend test --home ~/sentinel-dvpncli --recover"

alias show="sentinel-dvpncli query account \$(sentinel-dvpncli keys show mydvpn --keyring.backend test --home ~/sentinel-dvpncli --address) --node https://rpc.sentinel.co:443 --chain-id sentinelhub-2"

alias mydvpn="sentinel-dvpncli tx subscription-start 3 \
  --denom udvpn \
  --tx.from-name mydvpn \
  --keyring.backend test \
  --home ~/sentinel-dvpncli \
  --chain-id sentinelhub-2 \
  --node https://rpc.sentinel.co:443 \
  --tx.gas-prices 0.1udvpn \
  --tx.gas-adjustment 1.5 \
  --yes"
alias balance='sentinel-dvpncli keys show mydvpn --keyring.backend test --home ~/sentinel-dvpncli && echo "=== BALANCE ===" && sentinel-dvpncli query account $(sentinel-dvpncli keys show mydvpn --keyring.backend test --home ~/sentinel-dvpncli | grep address: | awk "{print \$2}") --rpc.addrs https://rpc.sentinel.co:443'


alias node-status="sentinel-dvpncli status --node https://rpc.sentinel.co:443"

# Quick key check
alias mykey="sentinel-dvpncli keys show mydvpn --keyring.backend test --home ~/sentinel-dvpncli"

# ---------------- General Useful Aliases ----------------
alias ll='ls -lah --color=auto'
alias la='ls -A'
alias l='ls -CF'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

alias df='df -h'
alias du='du -sh'

# Sentinel directory
alias sdc='cd ~/sentinel-dvpncli'

# Reload bashrc
alias reload='source ~/.bashrc'

# Prompt
PS1='\[\e[32m\]\u@\h\[\e[00m\]:\[\e[34m\]\w\[\e[00m\]\$ '

echo "✅ Sentinel aliases loaded"
