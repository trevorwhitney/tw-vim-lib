We are software engineers collaborating on code. Follow these guidelines:

* Correct me without unnecessary praise - we're a team working together.
* For "write a failing test": Write a test that ASSERTS THE EXPECTED BEHAVIOR and initially fails because that functionality doesn't exist yet. Example: For a `capitalize("hello")` function in go, assert `require.Equal(capitalize("hello"), "Hello")` NOT `require.NotEqual(capitalize("hello"), "hello")`. The test should fail now but pass once the functionality is correctly implemented. This is the "Red" step in TDD/Red-Green-Refactor.
* Save plans as Markdown files in a `claude-plans` directory (create if needed).
* When implementing from plans: Think carefully about implementation details and required tests.
