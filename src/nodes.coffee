$ = require('JSONSelect').match
pj = require 'prettyjson'
p = (obj) -> console.log pj.render obj, noColor: true
TypeScript = require './typescript'

mapClass = (Class, arr) -> arr.map (i) -> new Class(i)

listToJSON = (list) -> list.map (i) -> i.toJSON()

tokenKindToTypeKeyword = (tokenKind) ->
  for key, val of TypeScript.SyntaxKind
    if val is tokenKind then return key
  ''

tokenKindToTypeName = (tokenKind)->
  keyword = tokenKindToTypeKeyword(tokenKind)
  switch keyword
    when 'StringKeyword' then 'String'
    when 'NumberKeyword' then 'Number'
    when 'BooleanKeyword' then 'Boolean'
    when 'AnyKeyword' then 'Any'
    when 'VoidKeyword' then 'Void'
    when 'IdentifierName' then 'Identifier'

itemOrElements = (node) ->
  if node.item then [node.item]
  else if node.elements then node.elements
  else []

itemOrNodeOrTokens = (node) ->
  if node.item then [node.item]
  else if node.nodeOrTokens then node.nodeOrTokens
  else []

typeToTypeName = (type) ->
  type._fullText ? tokenKindToTypeName type.tokenKind

isFunctionNode = (node) -> node.callSignature?

exports.Node = Node = class Node
  constructor: (@ast) ->

  $: (query) -> $ query, @ast

  $first: (query) -> @$(query)[0]

  toJSON: -> throw 'Not implemented'

walkSymbol = (root)->
  if root.dotToken
    (new MemberAccess root).toJSON()
  else
    return root._fullText if root._fullText?
    tokenKindToTypeName (root.tokenKind ? root.name.tokenKind)

class MemberAccess extends Node
  """
  A.B.Point

  left:
    left:
      _fullText: A
    dotToken: ...
    right:
      _fullText: B
  dotToken: ...
  right:
    _fullText: Point
  """
  constructor: (@ast) ->
  toJSON: ->
    left = walkSymbol @ast.left
    right = walkSymbol @ast.right
    { left, right, nodeType: 'MemberAccess' }

class AnnotatedType extends Node
  '''
  TemplateApplication

    name:
      _fullText: Array
    typeArgumentList:
      typeArguments:
        item:
          _fullText: T

  simple
    _fullText: Array
    tokenKind: 11
  '''

  typeName: ->
    return walkSymbol @ast.type.name if @ast.type?.name?

    fullText = @$first(':root ._fullText') ? @$first(':root > .name > ._fullText')
    return fullText if fullText?
    tokenKindToTypeName (@$first(':root > .tokenKind') ? @$first(':root .name > .tokenKind'))

  constructor: (@ast) ->

  isArray: -> @ast.openBracketToken? and @ast.closeBracketToken?

  typeArguments: ->
    header = ":root > .typeArgumentList > .typeArguments"
    items = @$(header + '> .item')
    items =
      if items.length > 0 then items
      else
        items = @$first(header+'> .elements')?.filter (i) -> i.identifier?
        items ?= []

    items.map (i) ->
      if i.name?
        elements =
          if i.typeArgumentList.typeArguments.item
            [i.typeArgumentList.typeArguments.item]
          else if i.typeArgumentList.typeArguments
            i.typeArgumentList.typeArguments.elements
          else
            []
        annotatedTypes = mapClass AnnotatedType, elements
        {
          typeName: walkSymbol(i.name)
          typeArguments: listToJSON annotatedTypes
        }
      else
        typeArgumentName: walkSymbol i

  toJSON: ->
    {
      nodeType: @constructor.name
      typeName: @typeName()
      typeArguments: @typeArguments()
      isArray: @isArray()
    }

class TypeParameter extends Node
  '''
    typeParameters:
      item:
        identifier:
          _fullText: T
        constraint: null
  '''
  constructor: (@ast) ->

  toJSON: ->
    header = ":root > .typeParameters"
    items = @$(header + '> .item')
    items =
      if items.length > 0 then items
      else
        items = @$first(header+'> .elements')?.filter (i) -> i.identifier?
        items ?= []
    items.map (i) ->
      {
        nodeType: @constructor.name
        typeParameterName: walkSymbol(i.identifier)
        constraint: i.constraint
      }

class FunctionNode extends Node
  '''
  Array<T>

    typeAnnotation:
    _data:      0
    colonToken:
      _fullText:           :
      tokenKind:           106
      _trailingTriviaInfo: 4
    type:
      _data:            0
      name:
        _fullText: Array
        tokenKind: 11
      typeArgumentList:
        _data:            0
        lessThanToken:
          tokenKind: 80
        typeArguments:
          item:
            _fullText: T
            tokenKind: 11
        greaterThanToken:
          tokenKind: 81
  '''
  constructor: (@ast) ->

  propertyName: ->
    return walkSymbol @ast.propertyName if @ast.propertyName?
    return walkSymbol @ast.identifier if @ast.identifier?

  typeAnnotation: ->
    args =  @_arguments()
    functionArgs = mapClass FunctionArgument, args
    returnType = new AnnotatedType @$first(':root > .callSignature > .typeAnnotation > .type')
    {
      nodeType: 'Function'
      returnType: returnType.toJSON()
      arguments: listToJSON functionArgs
    }

  _arguments: (query) ->
    header = ":root > .callSignature > .parameterList > .parameters"
    item = @$(header + '> .item')
    if item.length > 0 then item
    else
      args = @$first(header+'> .elements')?.filter (i) -> i.identifier?
      args ?= []

  toJSON: ->
    propertyName: @propertyName()
    typeAnnotation: @typeAnnotation()
    typeParameters: if @ast.callSignature.typeParameterList?
      new TypeParameter(@ast.callSignature.typeParameterList).toJSON()
    else null

class LambdaFunctionAnnotation extends Node
  '''
  typeParameterList:      null
  parameterList:
    _data:           0
    openParenToken:
      tokenKind: 72
    parameters:
      item:
        _data:             0
        dotDotDotToken:    null
        modifiers:

        identifier:
          _fullText: t
          tokenKind: 11
        questionToken:     null
        typeAnnotation:
          _data:      0
          colonToken:
            tokenKind: 106
          type:
            tokenKind: 67
        equalsValueClause: null
    closeParenToken:
      _fullText:           )
      tokenKind:           73
      _trailingTriviaInfo: 4
  equalsGreaterThanToken:
    _fullText:           =>
    tokenKind:           85
    _trailingTriviaInfo: 4
  type:
    tokenKind: 67
  '''
  constructor: (@ast) ->

  arguments: (query) ->
    header = ":root > .parameterList > .parameters"
    item = @$(header + '> .item')
    if item.length > 0 then item
    else
      args = @$first(header+'> .elements')?.filter (i) -> i.identifier?
      args ?= []

  _arguments: ->
    args =  @arguments()
    identifiers = mapClass FunctionArgument, args
    args = identifiers.map (ident) => ident.toJSON()

  typeAnnotation: ->
    returnTypeAnnotation = new AnnotatedType @$first(':root > .type')
    returnTypeAnnotation.toJSON()

  toJSON: ->
    nodeType: @constructor.name
    annotationType: 'lambdaFunctionType'
    typeAnnotation: @typeAnnotation()
    arguments: @_arguments()

class FunctionArgument extends Node
  '''
  Example: str:string
    dotDotDotToken:    null
    modifiers:

    identifier:
      _fullText: str
      tokenKind: 11
    questionToken:     null
    typeAnnotation:
      _data:      0
      colonToken:
        tokenKind: 106
      type:
        tokenKind: 69
    equalsValueClause: null
  '''

  constructor: (@ast) ->

  identifierName: -> walkSymbol @ast.identifier

  nullable: -> !!@ast.questionToken

  spriced: -> !!@ast.dotDotDotToken

  typeAnnotation: ->
    type = new AnnotatedType @$first(':root > .typeAnnotation > .type')
    type.toJSON()

  toJSON: ->
    nodeType: @constructor.name
    identifierName: @identifierName()
    typeAnnotation: @typeAnnotation()
    nullable: @nullable()
    spriced: @spriced()

class VariableNode extends Node
  constructor: (@ast) ->

  propertyName: ->
    walkSymbol(@ast.variableDeclarator.propertyName)

  typeAnnotation: ->
    # TODO: refactor
    type = @$first(':root > .variableDeclarator > .typeAnnotation > .type')
    if type?.parameterList?
      lambdaFunctionAnnotation = new LambdaFunctionAnnotation(type)
      return lambdaFunctionAnnotation.toJSON()
    else
      type = new AnnotatedType @$first(':root > .variableDeclarator > .typeAnnotation > .type')
      return type.toJSON()

  toJSON: ->
    nodeType: @constructor.name
    propertyName: @propertyName()
    typeAnnotation: @typeAnnotation()

class VariableDeclarationNode extends Node
  toJSON: ->
    {
      nodeType: @constructor.name
      propertyName: walkSymbol @ast.propertyName
      typeAnnotation: @typeAnnotation()
    }

  typeAnnotation: ->
    type = @$first(':root > .typeAnnotation > .type')
    if type?.parameterList?
      lambdaFunctionAnnotation = new LambdaFunctionAnnotation(type)
      return lambdaFunctionAnnotation.toJSON()
    else
      type = new AnnotatedType @$first(':root > .typeAnnotation > .type')
      type.toJSON()

class HeritageList extends Node
  '''
    nodeOrTokens:
      -
        extendsOrImplementsKeyword:
          _fullText:           extends
        typeNames:
          item:
            _fullText:           A
      -
        extendsOrImplementsKeyword:
          _fullText:           implements
        typeNames:
          elements:
            -
              _fullText: IF1
              tokenKind: 11
            -
              _fullText:           ,
              tokenKind:           79
            -
              _fullText:           IF2
              tokenKind:           11
  '''
  root: 'heritageClauses'
  constructor: (@ast) ->
  toJSON: ->
    items = itemOrNodeOrTokens @ast
    implementList = null
    extend = null

    items.forEach (item) =>
      heritageType = walkSymbol item.extendsOrImplementsKeyword
      types = itemOrElements(item.typeNames)
        .filter (i) -> i._fullText isnt ','
        .map (i) -> new AnnotatedType(i)
      switch heritageType
        when 'implements'
          if types.length > 0
            implementList = listToJSON types
        when 'extends'
          if types.length > 0
            extend = types[0].toJSON()
    {
      implementList: implementList
      extend: extend
    }

class ClassNode extends Node

  constructor: (@ast) ->

  getProperties: ->
    for el in @_classElements()
      if isFunctionNode(el)
        new FunctionNode(el)
      else
        new VariableNode(el)

  _classElements: ->
    item = @$(":root > .classElements > .item")
    if item.length > 0 then item
    else @$first(":root > .classElements > .nodeOrTokens") or []

  className: -> walkSymbol @ast.identifier

  toJSON: ->
    {
      nodeType: @constructor.name
      className: @className()
      properties: listToJSON @getProperties()
      typeParameters: if @ast.typeParameterList? then new TypeParameter(@ast.typeParameterList).toJSON() else null
      heritages: if @ast.heritageClauses then new HeritageList(@ast.heritageClauses).toJSON() else null
    }

class InterfaceNode extends Node
  '''
  _data:             0
  modifiers:
    item:
      _fullText:           export
      tokenKind:           47
      _trailingTriviaInfo: 4
  interfaceKeyword:
    _fullText:           interface
    tokenKind:           52
    _trailingTriviaInfo: 4
  identifier:
    _fullText:           IFoo
    tokenKind:           11
    _trailingTriviaInfo: 4
  typeParameterList: null
  heritageClauses:

  body:
    _data:           0
    openBraceToken:
      _fullText:           {
      tokenKind:           70
      _trailingTriviaInfo: 5
    typeMembers:
      _data:     0
      elements:
        -
          _data:          0
          propertyName:
            _fullText:          a
            tokenKind:          11
            _leadingTriviaInfo: 8
          questionToken:  null
          typeAnnotation:
            _data:      0
            colonToken:
              tokenKind: 106
            type:
              tokenKind: 60
        -
          _fullText:           ;
          tokenKind:           78
          _trailingTriviaInfo: 5
        -
          _data:          0
          propertyName:
            _fullText:          b
            tokenKind:          11
            _leadingTriviaInfo: 8
          questionToken:  null
          typeAnnotation:
            _data:      0
            colonToken:
              tokenKind: 106
            type:
              tokenKind: 67
        -
          _fullText:           ;
          tokenKind:           78
          _trailingTriviaInfo: 5
    closeBraceToken:
      _fullText:           }
      tokenKind:           71
      _trailingTriviaInfo: 5
  '''

  constructor: (@ast) ->

  interfaceName: -> walkSymbol @ast.identifier

  properties: ->
    typeMembers = @$first(':root > .body > .typeMembers')
    props = []
    if typeMembers.elements?
      for el in typeMembers.elements when el.propertyName
        props.push el
    else if typeMembers.item?
      props.push typeMembers.item

    props.map (i) =>
      if isFunctionNode(i)
        new FunctionNode(i)
      else
        new VariableDeclarationNode(i)

  toJSON: ->
    {
      nodeType: @constructor.name
      interfaceName: @interfaceName()
      properties: listToJSON @properties()
      typeParameters: if @ast.typeParameterList? then new TypeParameter(@ast.typeParameterList).toJSON() else null
      heritages: if @ast.heritageClauses then new HeritageList(@ast.heritageClauses).toJSON() else null
    }

exports.Module = Module = class Module extends Node

  constructor: (@ast) ->

  moduleName: ->
    return walkSymbol(@ast.item.name) if @ast.item?.name?
    return walkSymbol(@ast.name) if @ast.name?

  modules: ->
    item = @$(":root > .moduleElements > .item")
    if item.length > 0 then item
    else @$first(":root > .moduleElements > .nodeOrTokens")

  getModules: ->
    mods = @modules()
    mods = $(':root > *:has(.moduleKeyword)', mods)?.filter (m) -> m.moduleKeyword?
    mods ?= []
    mapClass Module, mods

  getClasses: ->
    mods = @modules()
    mods = $(':root > *:has(.classKeyword)', mods)?.filter (c) -> c.classKeyword?
    mods ?= []
    mapClass ClassNode, mods

  getInterfaces: ->
    mods = @modules()
    mods = $(':root > *:has(.interfaceKeyword)', mods)?.filter (c) -> c.interfaceKeyword?
    mods ?= []
    mapClass InterfaceNode, mods

  getFunctions: ->
    mods = @modules()
    mods = $(':root > *:has(.functionKeyword)', mods)?.filter (f) -> f.functionKeyword?
    mods ?= []
    mapClass FunctionNode, mods

  getVariables: ->
    mods = @modules()
    mods = $(':root > *:has(:root .variableDeclaration)', mods)?.filter (v) -> v.variableDeclaration?

    items = []
    mods.forEach (m) ->
      if elements = m.variableDeclaration.variableDeclarators.elements
        for el in elements when el.propertyName
          items.push el
      else if item = m.variableDeclaration.variableDeclarators.item
        items.push item
    mapClass VariableDeclarationNode, items

  getProperties: ->
    props = []
    [].concat(@getFunctions(), @getVariables())

  toJSON: ->
    nodeType: @constructor.name
    moduleName: @moduleName()
    modules   : listToJSON @getModules()
    classes   : listToJSON @getClasses()
    properties: listToJSON @getProperties()
    interfaces: listToJSON @getInterfaces()

exports.TopModule = TopModule = class TopModule extends Module
  moduleName: -> 'Top'
  constructor: (@ast) ->
