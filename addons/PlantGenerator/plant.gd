@tool
@icon("./Assets/icon.svg")
class_name PlantGenerator
extends RefCounted

const Calculator = preload("./Calculation/calculator.gd")
const Sentence = Calculator.Sentence
const Symbol = Calculator.Symbol
const BUILT_IN_RULES: Dictionary[String, String] = {
    "c": "d",
    "d": "e",
    "e": "f",
    "f": "F",
    "i": "j",
    "j": "k",
    "k": "l",
    "l": "L",
}
var sentence: Sentence = null

var axiom: String = "F":
    set(value):
        axiom = value
        recalculate()

var rules: Dictionary[String, String] = {
    "F": "F[+F]F[-F]F"
}:
    set(value):
        rules = value
        recalculate()

var steps: int = 3:
    set(value):
        steps = value

var max_steps: int = 5:
    set(value):
        max_steps = value
        recalculate()

var branch_length_randomness: float = 0.0:
    set(value):
        branch_length_randomness = value
        recalculate()

var branch_width: float = 20.0:
    set(value):
        branch_width = value
        recalculate()


func _init(axiom_: String, rules_: Dictionary[String, String], steps_: int, max_steps_: int, branch_length_randomness_: float, branch_width_: float) -> void:
    axiom = axiom_
    rules = rules_
    steps = steps_
    max_steps = max_steps_
    branch_length_randomness = branch_length_randomness_
    branch_width = branch_width_


func _ready() -> void:
    sentence = Calculator.string_to_sentence(axiom, Calculator.Attributes.new(branch_width, branch_width))
    recalculate()

func grow_one_step() -> void:
    if not sentence:
        return
    var merged: Dictionary[String, String] = rules.duplicate()
    merged.merge(BUILT_IN_RULES)
    sentence = Calculator.advance_one_step(sentence, merged, branch_width, branch_length_randomness)


func recalculate() -> void:
    if not sentence:
        return
    var merged: Dictionary[String, String] = rules.duplicate()
    merged.merge(BUILT_IN_RULES)
    sentence = Calculator.calculate(Calculator.string_to_sentence(axiom, Calculator.Attributes.new(branch_width, branch_width)), merged, steps, branch_width, branch_length_randomness)
