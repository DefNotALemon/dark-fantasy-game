# Play

Static arcade for games that can launch in a browser. After GitHub Pages is enabled on this repo:

**https://defnotalemon.github.io/dark-fantasy-game/**

## On the cabinet

| Game | In browser? | Notes |
| --- | --- | --- |
| **Voidmaw** | Yes | Vendored from [DefNotALemon/voidmaw](https://github.com/DefNotALemon/voidmaw). Arcade shooter, one HTML file. |
| **Myrkfell** | Not yet | This Godot 4.7 Forward Plus prototype. Page explains how to run it in the editor. |

Other public repos on the same account (profile config, AIDungeon, ILOVEYOU) are not web games and are not listed.

## Local

```bash
python3 -m http.server 8080 --directory site
```

Then open http://127.0.0.1:8080/

## Deploy

`.github/workflows/pages.yml` publishes the `site/` folder to GitHub Pages on push to `main`. First live deploy needs Pages set to **GitHub Actions** (Settings → Pages) if the workflow has not created that source yet.
