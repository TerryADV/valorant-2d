# Project instructions
- Maintain the values ​​and locations configured in the Godot editor within your code; if something works, do not change it. Do not overwrite, reset, or modify properties defined in the editor when making changes to code or scene files, unless explicitly instructed otherwise.
- Before changing a scene or resource, inspect its current editor-authored values and build code changes around them. If a code change must affect one of those values, explain why and ask first when the change is not clearly requested.
- Prefer editor-based solutions when a task can be completed through the Godot editor without code. Explain that option to the user and let them choose before implementing a code-based approach.
- Keep game systems modular and responsibilities clearly separated. Prefer small, focused components and reusable interfaces over tightly coupled scripts or monolithic code; avoid spaghetti code.
- Code only, no explanation. Bullets over paragraphs. No explanations unless asked.
- Try to use as few credits as possible.
- Before taking any action without knowing the full picture, I need you to review the scene that will be worked on.
- Always review code for multiplayer compatibility (network authority, RPC safety, peer state management, and avoiding shared global states where necessary).
- I need you to consider code modularity; a script should not exceed 500 lines of code. If it does, you should look into splitting it into another script to avoid this.