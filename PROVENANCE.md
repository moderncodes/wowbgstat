# Voice line provenance — bgstat killing-blow audio

Keep this in the repo root. It is the answer to "where did these come
from?" if a CurseForge moderator or anyone else ever asks.

## How these were made

Text-to-speech, synthesized locally, then processed to sound like a
radio transmission. No human performance was recorded, sampled,
licensed, or redistributed. No third-party audio of any kind is
included.

| Step                      | Tool / asset                  | License                                                         |
|---------------------------|-------------------------------|-----------------------------------------------------------------|
| Synthesis                 | Piper TTS 1.7.0               | MIT                                                             |
| Voice model               | `en_US-norman-medium`         | trained from scratch on LibriVox recordings — **public domain** |
| Post-processing           | ffmpeg                        | LGPL/GPL (tool only; does not affect output)                    |
| Key-up burst, noise floor | generated noise (`anoisesrc`) | n/a — synthesized, not sampled                                  |

Voice model card:
https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/norman/medium/MODEL_CARD

Deliberately NOT used: Piper voices `ryan` and `hfc_male`, both
CC BY-NC-SA 4.0, unusable on a monetized distribution platform.

## Rights position

- No attribution required by any upstream license.
- Nothing is redistributed as third-party stock; this is generated
  output, not a licensed sample.
- Pure AI output is not copyrightable in the US, so these files are not
  protectable. Irrelevant for this use, but worth knowing.

## Reproduction recipe

Synthesis (Piper), per line:
    voice: en_US-norman-medium
    length_scale=1.22  noise_scale=0.72  noise_w_scale=0.9

Voice chain (ffmpeg):
    asetrate=22050*0.89 -> aresample=22050 -> atempo=1.12   (down ~2 semitones)
    -> silenceremove(-45dB, 0.02 lead / 0.10 tail)
    -> highpass=280Hz -> lowpass=3400Hz
    -> acompressor(threshold=-24dB, ratio=10, attack=2, release=45)
    -> volume=+11dB -> alimiter=limit=0.94

Key-up burst (0.13s, prepended):
    anoisesrc d=0.13 c=white a=0.9
    -> highpass=420Hz -> lowpass=3200Hz
    -> equalizer f=1600 t=q w=1.2 g=8
    -> afade out st=0.005 d=0.125 curve=exp
    -> volume=0.55

Noise floor (runs under the voice, ends 0.09s after it, no fade —
this abrupt stop is the carrier drop):
    anoisesrc d=(voice+0.09) c=pink a=0.9
    -> highpass=500Hz -> lowpass=2600Hz -> volume=0.055

Assembly:
    voice delayed 25ms, mixed over noise floor (amix normalize=0)
    -> key-up burst prepended
    -> loudnorm I=-15 TP=-1.5 LRA=11
    -> mp3 128k / 44.1kHz mono

## Lines

| File              | Text                            |
|-------------------|---------------------------------|
| BarelyFelt.mp3    | Barely felt that.               |
| CorpseRun.mp3     | Corpse run's that way.          |
| Deleted.mp3       | Deleted.                        |
| Deprioritized.mp3 | Subject has been deprioritized. |
| ForFree.mp3       | I do this for free.             |
| KillLogged.mp3    | Kill logged.                    |
| ResTimer.mp3      | Enjoy the res timer.            |
| SitDown.mp3       | Sit down.                       |
| ThePile.mp3       | Another one for the pile.       |
