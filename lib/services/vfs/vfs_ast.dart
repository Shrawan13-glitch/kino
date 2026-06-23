sealed class AstNode {}

class ProgramNode extends AstNode {
  final List<AstNode> statements;
  ProgramNode(this.statements);
}

class SeqNode extends AstNode {
  final List<AstNode> nodes;
  SeqNode(this.nodes);
}

enum AndOrOp { and, or }

class AndOrNode extends AstNode {
  final AstNode left;
  final AndOrOp op;
  final AstNode right;
  AndOrNode(this.left, this.op, this.right);
}

class PipelineNode extends AstNode {
  final List<AstNode> commands;
  PipelineNode(this.commands);
}

class BackgroundNode extends AstNode {
  final AstNode command;
  BackgroundNode(this.command);
}

class RedirectNode {
  final int srcFd;
  final String op;
  final String target;
  String? heredocContent;

  RedirectNode(this.srcFd, this.op, this.target, {this.heredocContent});

  bool get isInput => srcFd == 0;
  bool get isOutput => srcFd == 1 || srcFd == 2 || srcFd == -1;
  bool get isAppend => op == '>>';
  bool get isHereDoc => op == '<<';
  bool get isHereStr => op == '<<<';
}

class SimpleCmdNode extends AstNode {
  final List<String> words;
  final List<RedirectNode> redirects;
  final bool background;
  SimpleCmdNode({
    required this.words,
    this.redirects = const [],
    this.background = false,
  });
}

class IfNode extends AstNode {
  final AstNode condition;
  final AstNode thenBody;
  final List<ElifPair> elifs;
  final AstNode? elseBody;
  IfNode(this.condition, this.thenBody, {this.elifs = const [], this.elseBody});
}

class ElifPair {
  final AstNode condition;
  final AstNode body;
  ElifPair(this.condition, this.body);
}

class WhileNode extends AstNode {
  final AstNode condition;
  final AstNode body;
  WhileNode(this.condition, this.body);
}

class UntilNode extends AstNode {
  final AstNode condition;
  final AstNode body;
  UntilNode(this.condition, this.body);
}

class ForNode extends AstNode {
  final String variable;
  final List<String> words;
  final AstNode body;
  ForNode(this.variable, {this.words = const [], required this.body});
}

class CForNode extends AstNode {
  final String? init;
  final String? condition;
  final String? increment;
  final AstNode body;
  CForNode({this.init, this.condition, this.increment, required this.body});
}

class SelectNode extends AstNode {
  final String variable;
  final List<String> words;
  final AstNode body;
  SelectNode(this.variable, this.words, this.body);
}

class CoprocNode extends AstNode {
  final String? name;
  final AstNode body;
  CoprocNode({this.name, required this.body});
}

class CaseNode extends AstNode {
  final String word;
  final List<CaseItemNode> items;
  CaseNode(this.word, this.items);
}

class CaseItemNode {
  final List<String> patterns;
  final AstNode body;
  CaseItemNode(this.patterns, this.body);
}

class FunctionDefNode extends AstNode {
  final String name;
  final AstNode body;
  FunctionDefNode(this.name, this.body);
}

class BlockNode extends AstNode {
  final AstNode body;
  BlockNode(this.body);
}

class SubshellNode extends AstNode {
  final AstNode body;
  SubshellNode(this.body);
}

class AssignmentNode extends AstNode {
  final String name;
  final String value;
  AssignmentNode(this.name, this.value);
}

class ArrayAssignmentNode extends AstNode {
  final String name;
  final List<String> values;
  ArrayAssignmentNode(this.name, this.values);
}

class BreakNode extends AstNode {
  final int count;
  BreakNode(this.count);
}

class ContinueNode extends AstNode {
  final int count;
  ContinueNode(this.count);
}

class ReturnNode extends AstNode {
  final int code;
  ReturnNode(this.code);
}

class ExitNode extends AstNode {
  final int code;
  ExitNode(this.code);
}
