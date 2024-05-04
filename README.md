# Tools Repository

In this repository you'll find a number of different commonly used tools that I have created over the years.

## Ellis::Tools Module

The `Ellis::Tools` module is designed to enhance the Rails development experience by providing utility functions that assist in the annotation, debugging, and performance benchmarking of ActiveRecord models and Rails controllers. This module is especially useful for developers who need to quickly understand and document the structure of Rails applications, and is intended to be used in the console.

### Features

- **Model and Controller Annotations**: Automatically generate detailed annotations for ActiveRecord models and Rails controllers, outlining their structure and relationships.
- **Benchmarking Utilities**: Compare the performance of methods within your models or any other Ruby code.
- **Data Inspection**: Extract and display data from ActiveRecord objects, which can be particularly helpful for debugging and ensuring data integrity.


### Usage

##### Annotating Models and Controllers
You can annotate your models and controllers to get a detailed schema or structure directly from your Rails console.

Provides a detailed annotation of ActiveRecord models or Rails controllers using the Audited gem. This method can output annotations directly to the console, copy them to the clipboard, or append them to the relevant model or controller files.

It is designed to help developers quickly understand the structure and relationships of various components in their application.

Here's how to use this feature:

```ruby
# Load the tools in your Rails console
# Usage:
  load '/{path to file}/tools.rb'
  Ellis::Tools.annotate [Model], *options

# Example:
  Ellis::Tools.annotate User, to_file: true

# Options:
  :to_clipboard - (Boolean) Whether to copy the output to the clipboard. Default: true.
  :to_screen - (Boolean) Whether to display the output on the screen. Default: true.
  :to_file - (Boolean) Whether to append the output to the model's file. Default: false.
```

(there is more I just need to update this file at some point....)