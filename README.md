# sahur

*tung tung tung sahur. answer him.*

Jogo de terror em primeira pessoa (Godot 4.4, Linux). Você é o **operativo 03** da **hush**
(*hollow underlayer surveillance & holding*), enviado para baixo do feed, no labirinto onde o
Tung Tung Tung Sahur anda. Todas as luzes estão acesas, o ar é denso, e você vê tudo pelos óculos
**hush nv-7**, que ficam presos ao rosto: não existe opção de tirá-los.

## Controles

| tecla | ação |
|---|---|
| WASD | andar |
| mouse | olhar |
| Q | gritar "sahur!" (responda quando ele chamar, e nunca quando ele não chamar) |
| E / clique | interagir (notas) |
| Ctrl | agachar |
| Espaço | pular |
| Esc | pausa / configurações |

## Rodar

```bash
godot --path . 
```

Ou exporte o executável Linux:

```bash
godot --headless --path . --export-release "Linux" build/Sahur.x86_64
```

## Como foi feito (tudo em código)

- `scripts/tung_model.gd`: o Tung esculpido vértice a vértice (rosto entalhado, olhos, pálpebras, braços, taco torneado).
- `scripts/carved_wood.gdshader`, `scripts/eye.gdshader`: madeira envernizada e olho úmido.
- `scripts/post.gdshader`: imagem dos óculos (ganho automático, ruído de sensor), olho de peixe, motion blur.
- `scripts/levels/level_0.gd`: o labirinto todo aceso, névoa de profundidade estilo Source, poeira, halos nas lâmpadas.
- `scripts/hud.gd`: hud source × iphone, giroscópio/horizonte artificial e telemetria do visor.
- `scripts/player.gd`: head bob, tilt, mola de inércia e acelerômetro que alimentam o giroscópio.
- `tools/sound_design.py`: todos os sons sintetizados em Python (numpy/scipy), sem samples.
  Para regenerar: `pip install numpy scipy && python3 tools/sound_design.py`.
- `tools/demo.gd`: piloto automático usado para gravar o vídeo.

Fonte: Inter (SIL Open Font License, ver `fonts/Inter-LICENSE-OFL.txt`).

## iPhone (.ipa)

Cada push na branch `main` dispara o workflow `.github/workflows/ios.yml`, que roda num Mac do
GitHub, exporta o projeto Xcode pelo Godot e compila um `.ipa` **não assinado**. Ele aparece em
**Releases** e como artefato da execução em **Actions**.

Para instalar sem Mac:

1. Baixe o `Sahur.ipa` da página de Releases.
2. Instale um sideloader. No **Linux**: PlumeImpactor (Flathub `dev.khcrysalis.PlumeImpactor`,
   precisa do `usbmuxd`). No Windows/macOS: Sideloadly ou AltStore.
3. Conecte o iPhone pelo cabo, arraste o `.ipa` e entre com a sua Apple ID (uma conta grátis serve).
4. No iPhone: Ajustes → Geral → VPN e Gerenciamento de Dispositivos → confie no seu perfil.
5. No iOS 16 ou mais novo, ative também o Modo de Desenvolvedor (Ajustes → Privacidade e Segurança).

Com Apple ID grátis o app precisa ser reinstalado a cada 7 dias.

No iPhone: joystick à esquerda para andar, arraste à direita para olhar. Quando o Tung chamar
("tung tung tung… sahur"), **toque na tela** para responder. **e** interage, **crouch** agacha
e **ii** pausa.
