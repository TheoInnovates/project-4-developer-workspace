"""
title: Calculator
author: local
version: 0.1.0
license: MIT
description: Evaluates arithmetic/math expressions exactly via a safe AST evaluator (no eval, no LLM mental math).
"""
import ast
import math
import operator


class Tools:
    def __init__(self):
        pass

    def calculate(self, expression: str) -> str:
        """
        Evaluate a mathematical expression and return the exact result. Use for any
        arithmetic the user needs computed precisely: +, -, *, /, //, %, ** and
        functions like sqrt, sin, cos, tan, log, log10, exp, floor, ceil, factorial.
        Constants pi, e, tau are available.
        :param expression: The math expression, e.g. "sqrt(2)*3 + 17 % 5" or "2**10".
        :return: The computed result, or an error message if the expression is invalid.
        """
        ops = {
            ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
            ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv,
            ast.Mod: operator.mod, ast.Pow: operator.pow,
            ast.USub: operator.neg, ast.UAdd: operator.pos,
        }
        funcs = {n: getattr(math, n) for n in (
            "sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "log2",
            "log10", "exp", "floor", "ceil", "fabs", "factorial", "gcd", "pow",
        )}
        consts = {"pi": math.pi, "e": math.e, "tau": math.tau}

        def ev(node):
            if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
                return node.value
            if isinstance(node, ast.BinOp):
                return ops[type(node.op)](ev(node.left), ev(node.right))
            if isinstance(node, ast.UnaryOp):
                return ops[type(node.op)](ev(node.operand))
            if isinstance(node, ast.Name) and node.id in consts:
                return consts[node.id]
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                    and node.func.id in funcs):
                return funcs[node.func.id](*[ev(a) for a in node.args])
            raise ValueError("unsupported expression")

        try:
            return str(ev(ast.parse(expression, mode="eval").body))
        except Exception as e:
            return f"Error: {e}"
