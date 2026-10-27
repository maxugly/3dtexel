import type { ProviderFactory } from "../types.js";
import { ambientCgFactory } from "./ambientcg.js";
import { blendswapFactory } from "./blendswap.js";
import { cgtraderFactory } from "./cgtrader.js";
import { kenneyFactory } from "./kenney.js";
import { metMuseumFactory } from "./met-museum.js";
import { nasaFactory } from "./nasa.js";
import { openGameArtFactory } from "./opengameart.js";
import { openverseFactory } from "./openverse.js";
import { polyhavenFactory } from "./polyhaven.js";
import { texelFactory } from "./texel.js";
import { wikimediaFactory } from "./wikimedia.js";

export const builtInProviders: ProviderFactory[] = [
  polyhavenFactory,
  ambientCgFactory,
  openGameArtFactory,
  openverseFactory,
  metMuseumFactory,
  wikimediaFactory,
  nasaFactory,
  kenneyFactory,
  blendswapFactory,
  cgtraderFactory,
  texelFactory
];
