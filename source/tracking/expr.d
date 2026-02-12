module tracking.expr;

// Lightweight expression shim for nijimi tracking migration.
// The original nijiexpose implementation depends on lumars/lua runtime;
// this placeholder keeps the binding graph compilable until evaluator
// integration is wired on the nijimi side.

string insExpressionGenerateSignature(uint uuid, int axis) {
    return "expr_" ~ uuid.to!string ~ "_" ~ axis.to!string;
}

struct Expression {
private:
    string signature_;
    string expression_;
    string lastError_;

public:
    this(string signature, string expr) {
        signature_ = signature;
        expression_ = expr;
        lastError_ = null;
    }

    string signature() const {
        return signature_;
    }

    string expression() const {
        return expression_;
    }

    void expression(string expr) {
        expression_ = expr;
    }

    string lastError() const {
        return lastError_;
    }

    float call() {
        // TODO: port full evaluator from nijiexpose when needed.
        return 0.0f;
    }
}

import std.conv : to;

