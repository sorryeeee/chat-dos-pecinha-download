# Chat dos Pecinha — Download

Repositório público **somente para instalação e atualização**.

O código-fonte do aplicativo fica em um repositório privado separado.

## Instalar / atualizar

```powershell
irm "https://raw.githubusercontent.com/sorryeeee/chat-dos-pecinha-download/main/bootstrap.ps1?x=$(Get-Random)" | iex
```

Versão atual: `1.3.25.6.8.6.6-online-1`

## Conteúdo deste repositório

- `bootstrap.ps1`
- `install.ps1`
- `release/latest.zip`
- `release/latest.sha256`
- pacote versionado e SHA-256

Não coloque `src/`, `payload/`, ferramentas de desenvolvimento ou
arquivos de estado/autenticação neste repositório.


## 1.3.25.6.8.6.2-online-1 — logo oficial

A imagem do mascote preto com detalhes dourados agora é a identidade oficial no header, login, janela, tray, taskbar e atalhos.


## 1.3.25.6.8.6.3-online-1 — Logo asset hotfix

Corrige o updater para instalar `desktop/brand-logo.png`.
A logo oficial agora é copiada tanto em instalação nova quanto em atualização.


## 1.3.25.6.8.6.4-online-1 — Logo CSP final fix

A logo visível do header/login/rodapé agora é embutida como `data:` no HTML.
Isso elimina dependência de resolução `file://` e evita bloqueio por CSP.
Tray, janela e atalho continuam usando os assets PNG/ICO locais.


## Atualização automática

Versão obrigatória: `1.3.25.6.8.6.5-online-1`. O HOST consulta `release/version.json` e avisa clientes em tempo real.


## 1.3.25.6.8.6.6-online-1

Metadados de versão dos demais clientes são exibidos somente para o admin.
O mecanismo de atualização automática continua igual para todos.
