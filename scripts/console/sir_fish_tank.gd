extends SubViewportContainer
## Sir Fish's tank (spec 17.7). A glass bowl bolted into the console's resource
## strip, and instanced a second time at 2x in the run summary's header
## (spec 18.2).
##
## [move-elements-to-editor] The bowl used to be assembled in _ready(); it is
## authored in sir_fish_tank.tscn now, under FishViewport/Tank:
##
##     WaterBackdrop  lit disc BEHIND the fish. The viewport is transparent_bg,
##                    so without it the glass tints straight onto the console's
##                    near-black panel and the tank reads as a dark blob with a
##                    fish-shaped smudge in it.
##     Glass          the bowl itself, on water.gdshader (depth_draw_never, so
##                    the fish reads through it).
##     Base/Gravel    gold stand and gravel bed.
##     Plaque         + PlaqueText, a Label3D so no font asset is ever baked
##                    into a mesh (spec 23.5).
##
## Nothing about that needed to be code - each instance of this scene gets its
## own copy of the authored children exactly as it got its own built ones, and
## every radius, colour and offset is now inspector-editable.
