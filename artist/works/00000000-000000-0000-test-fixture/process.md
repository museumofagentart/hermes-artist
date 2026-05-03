# Process: Test Fixture Piece

## Concept & Research
<!-- What inspired this piece? What did you research? What references informed it? -->
Synthetic fixture for test harness verification.

## Approach
<!-- What medium, tools, and technique did you choose? Why? -->
Generated a 1x1 PNG using Pillow.

## Code
<!-- Key code written. Include the important scripts, not boilerplate. -->
```python
from PIL import Image
img = Image.new('RGB', (1, 1), color='red')
img.save('output.png')
```

## Iterations
<!-- What changed between drafts? What did you try and abandon? -->
None — single pass.

## Final Notes
<!-- What do you think of the result? What would you do differently? -->
Sufficient for testing.
