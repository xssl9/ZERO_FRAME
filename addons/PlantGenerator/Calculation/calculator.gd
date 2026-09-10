extends RefCounted


class Attributes:
    var current_width: float
    var desired_width: float
    var length_factor: float
    var angle_factor: float

    func _init(current_width_: float, desired_width_: float, length_factor_: float = 1.0) -> void:
        self.current_width = current_width_
        self.desired_width = desired_width_
        self.length_factor = length_factor_


class Symbol:
    var character: String
    var attributes: Attributes

    func _init(character_: String, attributes_: Attributes) -> void:
        self.character = character_
        self.attributes = attributes_


class Sentence:
    var symbols: Array[Symbol]

    var text: String:
        get():
            var result: String = ""
            for symbol: Symbol in symbols:
                result += symbol.character
            return result

    func _init(symbols_: Array[Symbol]) -> void:
        self.symbols = symbols_


static func calculate_widths(sentence: Sentence, base_width: float) -> Sentence:
    var bottom_widths: Array[float] = []
    var top_widths: Array[float] = []
    var above: Array[float] = [base_width]
    var text: String = sentence.text
    for character: String in text.reverse():
        bottom_widths.push_front(above[-1])
        if character == "]":
            above.push_back(base_width)
        elif character == "[":
            var closed_branch_width: float = above.pop_back()
            above[-1] = sqrt(pow(above[-1], 1.9) + pow(closed_branch_width, 1.9))

    for i: int in range(len(bottom_widths)):
        sentence.symbols[i].attributes.desired_width = bottom_widths[i]

    return sentence


static func calculate_random_factors(sentence: Sentence, branch_length_randomness: float) -> Sentence:
    for symbol: Symbol in sentence.symbols:
        if symbol.character == "f":
            symbol.attributes.length_factor = 1.0 + (branch_length_randomness * (randf() - 0.5))
    return sentence


static func calculate(sentence: Sentence, rules: Dictionary, steps: int, base_width: float, branch_length_randomness: float) -> Sentence:
    for i: int in range(steps):
        sentence = advance_one_step(sentence, rules, base_width, branch_length_randomness)
    return sentence


static func advance_one_step(sentence: Sentence, rules: Dictionary, base_width: float, branch_length_randomness: float) -> Sentence:
    var new_sentence: Sentence = Sentence.new([])
    for symbol: Symbol in sentence.symbols:
        if rules.has(symbol.character):
            for i: int in range(len(rules[symbol.character])):
                new_sentence.symbols.append(Symbol.new(rules[symbol.character][i], Attributes.new(symbol.attributes.desired_width, symbol.attributes.desired_width, symbol.attributes.length_factor)))
        else:
            new_sentence.symbols.append(Symbol.new(symbol.character, Attributes.new(symbol.attributes.desired_width, symbol.attributes.desired_width, symbol.attributes.length_factor)))
    new_sentence = calculate_widths(new_sentence, base_width)
    new_sentence = calculate_random_factors(new_sentence, branch_length_randomness)
    return new_sentence


static func string_to_sentence(string: String, attributes: Attributes) -> Sentence:
    var symbols: Array[Symbol] = []
    for i: int in range(string.length()):
        symbols.append(Symbol.new(string[i], attributes))
    var sentence: Sentence = Sentence.new(symbols)
    return sentence
