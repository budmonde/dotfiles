# Global Coding Guidelines

## Comments

Only include comments when they provide necessary context or explanation that isn't already
obvious from the code itself. If the code is human-readable and self-explanatory, omit the
comment. Prefer clear, descriptive names over comments that restate what the code does.

## Code Change Order

If a repository/project contains a test suite, whenever making suggested changes, run the
test suite before and after the change. If the code change is prompted by the existence of
a bug, always attempt to first implement the test case that triggers the bug, followed by
a suggested fix for the bug before finally running the test suite to ensure the identified
bug has been fixed.
