# Type inference

With type inference, the data type of an expression can be deduced, which allows providing meaningful autocompleter 
suggestions or documentation for a class or method.

The type inference strategies below take only the global scope into account (e.g. like when evaluating a simple line on the console).
For longer console input or complete ruby files, one would have to consider nested scopes and visibility of variables by building an abstract syntax tree out of the complete code.

## Forward Evaluation Resolver

    first identifier → token → next token → …

Tries to find the object corresponding to the first identifier, then evaluates subsequent tokens
using introspection where possible.

<dl>
<dt>TokenClassificationByObject:</dt>
<dd>We have a reference to the exact object in ObjectSpace.</dd>
<dt>TokenClassificationByClass:</dt>
<dd>We know the class in ObjectSpace, but we don't have an instance of it.</dd>
<dt>TokenClassificationByDoc:</dt>
<dd>Fallback to documentation to know what type a method returns (since Ruby is not 
statically 
typed, introspection cannot provide the return types). We use statically generated documentation from yardoc. However documentation may sometimes be incomplete and miss return type information.</dd>
</dl>

<img alt="Forward evaluation state diagram" src="https://cdn.rawgit.com/Aerilius/sketchup-console-plus/d20b7e5b/design/forward_evaluation_resolver.svg">

### Example

```
model = Sketchup.active_model
model.selection
```

1. Search `model` in ObjectSpace  
  `TokenClassificationByObject(model, is_instance=true)`

2. Search an identifier `selection` in `Sketchup::Model` → We find a method, but don't know its return type.  
  `TokenClassificationByDoc("Sketchup::Model#selection", is_instance=true)`

3. Search `Sketchup::Model#selection` in yardoc documentation → It returns an `Sketchup::Selection`, but we don't have a reference to the exact instance.  
  `TokenClassificationByClass(Sketchup::Selection, is_instance=true)`

## Backtracking Resolver

This approach tries to guess the most likely type starting from the last token.
Since a token can be member of multiple classes or objects this results in a tree of possibilities, but it can be narrowed down by matches for the previous tokens.
 
    … → previous token → last token

1. Last token  
   ↓
2. Which types (previous token) respond to that token?  
   ↓
3. Which of these types can be returned by previous previous token?

Usually already with two tokens, the possibilities can be reduced to one.

### Example:

```ruby
unknown_reference.entities.length.to_s
```

1. Find classes that have a method `to_s`.  
  `Array#to_s`, **`Fixnum#to_s`**, `Float#to_s`, `Hash#to_s`, `NilClass#to_s`…

2. Then find classes that have a method `length` which returns an instance of the former classes.  
  `Array#length`, `Hash#length`, **`Sketchup::Entities#length`**, …

3. Then find classes that have a method `entities` and return a `Sketchup::Entities` (or `Array` or `Hash`).  
  **`Sketchup::Model#entities`**, **`Sketchup::Model#active_entities`**, **`Sketchup::ComponentDefinition#entities`**, 
**`Sketchup::Group#entities`**
