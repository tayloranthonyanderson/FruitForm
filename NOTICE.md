# NOTICE — licensing of source code vs. bundled models

FruitForm bundles trained machine-learning models alongside its source code, and
these two parts are licensed differently. This file explains the split.

## Source code — MIT

The application source code (the Swift/SwiftUI app and the Python scripts under
`ml/`) is licensed under the **MIT License**. See [LICENSE](LICENSE) for the full
text. You may reuse the source code under MIT.

## Bundled detector model — CC BY-NC-SA 4.0 (NonCommercial)

The bundled **detector** model (`FruitForm/Models/TomatoSegmenter.mlpackage`) is a
**derivative work** of the **LaboroTomato** dataset
(https://github.com/laboroai/LaboroTomato), which is licensed
**CC BY-NC-SA 4.0** (Creative Commons Attribution-NonCommercial-ShareAlike 4.0).

Under that license's **ShareAlike + NonCommercial + Attribution** terms, the
detector weights derived from LaboroTomato are themselves distributed under
**CC BY-NC-SA 4.0**. In practice this means the bundled detector weights:

- may be used for **non-commercial** purposes only;
- must carry **attribution** to LaboroTomato; and
- if redistributed, must keep the **same CC BY-NC-SA 4.0 license** (ShareAlike).

## Bundled classifier models — author's own data

The **classifier** models (`FruitForm/TomatoShapeNet.mlpackage` and
`FruitForm/TomatoRatingNet.mlpackage`) were trained by the author on the author's
own photographs of grocery-store tomatoes. **No proprietary or employer data** is
used in these models.

## Net effect

Because the bundled detector weights carry a **NonCommercial** license, the
repository **as a whole** (with the committed models) is intended for
**research / personal / non-commercial use only**.

The MIT-licensed **source code itself** may still be reused under the MIT License
— the NonCommercial restriction applies to the bundled detector weights, not to
the application code.
