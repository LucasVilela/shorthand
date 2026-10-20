import Foundation
import Testing
@testable import ShorthandCore

@Suite struct AbbreviationMatcherTests {
    @Test func matchesAbbreviationAtEndOfTypedText() {
        let matcher = AbbreviationMatcher(snippets: [Snippet(abbreviation: ";sig", content: "Cheers")])
        #expect(matcher.match(in: "hello ;sig")?.content == "Cheers")
        #expect(matcher.match(in: "hello ;si") == nil)
        #expect(matcher.match(in: ";sig ") == nil)
    }

    @Test func prefersTheLongestAbbreviation() {
        let matcher = AbbreviationMatcher(snippets: [
            Snippet(abbreviation: "date", content: "short"),
            Snippet(abbreviation: "ddate", content: "long"),
        ])
        #expect(matcher.match(in: "x ddate")?.content == "long")
        #expect(matcher.match(in: "x date")?.content == "short")
    }

    @Test func ignoresDisabledAndEmptyAbbreviations() {
        let matcher = AbbreviationMatcher(snippets: [
            Snippet(abbreviation: ";a", content: "off", isEnabled: false),
            Snippet(abbreviation: "", content: "empty"),
        ])
        #expect(matcher.match(in: ";a") == nil)
        #expect(matcher.match(in: "anything") == nil)
    }

    @Test func isCaseSensitive() {
        let matcher = AbbreviationMatcher(snippets: [Snippet(abbreviation: ";Sig", content: "x")])
        #expect(matcher.match(in: ";sig") == nil)
        #expect(matcher.match(in: ";Sig") != nil)
    }
}

@Suite struct TypingBufferTests {
    @Test func keepsOnlyTheLastCharactersUpToCapacity() {
        var buffer = TypingBuffer(capacity: 4)
        buffer.append("abcdef")
        #expect(buffer.text == "cdef")
    }

    @Test func deleteAndReset() {
        var buffer = TypingBuffer()
        buffer.deleteBackward()
        buffer.append("ab")
        buffer.deleteBackward()
        #expect(buffer.text == "a")
        buffer.reset()
        #expect(buffer.text.isEmpty)
    }
}

@Suite struct MacroExpanderTests {
    // 2026-10-20 23:30 UTC, which is already 21 Oct in Sydney.
    let now = Date(timeIntervalSince1970: 1_792_539_000)
    let utc = TimeZone(identifier: "UTC")!

    @Test func plainTextIsUnchanged() {
        let result = MacroExpander().expand("Hello ${name} { spaced } {a.b}")
        #expect(result == ExpansionResult(text: "Hello ${name} { spaced } {a.b}", cursorOffsetFromEnd: 0))
    }

    @Test func isoDateUsesTheTimeZone() {
        #expect(MacroExpander(now: now, timeZone: utc).expand("{isodate}").text == "2026-10-20")
        let sydney = TimeZone(identifier: "Australia/Sydney")!
        #expect(MacroExpander(now: now, timeZone: sydney).expand("{isodate}").text == "2026-10-21")
    }

    @Test func dateAndTimeFollowTheLocale() {
        let expander = MacroExpander(now: now, locale: Locale(identifier: "en_US_POSIX"), timeZone: utc)
        #expect(expander.expand("{date}").text == "Oct 20, 2026")
        #expect(expander.expand("{time}").text.hasPrefix("11:30"))
    }

    @Test func clipboardIsInsertedLiterally() {
        let expander = MacroExpander(clipboard: "{date} and {cursor}")
        let result = expander.expand("Copied: {clipboard}")
        #expect(result == ExpansionResult(text: "Copied: {date} and {cursor}", cursorOffsetFromEnd: 0))
    }

    @Test func cursorOffsetCountsCharactersAfterTheMarker() {
        let result = MacroExpander().expand("Thanks, {cursor}! 🎉")
        #expect(result.text == "Thanks, ! 🎉")
        #expect(result.cursorOffsetFromEnd == 3)
    }

    @Test func onlyTheFirstCursorCounts() {
        let result = MacroExpander().expand("a{cursor}b{cursor}c")
        #expect(result == ExpansionResult(text: "abc", cursorOffsetFromEnd: 2))
    }
}

@Suite struct SnippetDecodingTests {
    @Test func optionalFieldsDefault() throws {
        let json = #"[{"abbreviation": ";x", "content": "y"}]"#
        let snippets = try JSONDecoder().decode([Snippet].self, from: Data(json.utf8))
        #expect(snippets.first?.isEnabled == true)
        #expect(snippets.first?.label == "")
    }
}

@Suite struct FillInTemplateTests {
    @Test func plainContentHasNoFields() {
        let template = FillInTemplate("Hello ${name}, it's {date} {cursor}")
        #expect(template.fields.isEmpty)
        #expect(template.render(FillInValues()) == [.template("Hello ${name}, it's {date} {cursor}")])
    }

    @Test func parsesEachKindInOrder() {
        let template = FillInTemplate("{fill:Name} {fill:Notes:multi} {choice:Tone:warm|formal} {optional:PS}p{/optional}")
        #expect(template.fields == [
            FillInField(name: "Name", kind: .text),
            FillInField(name: "Notes", kind: .multilineText),
            FillInField(name: "Tone", kind: .choice, options: ["warm", "formal"]),
            FillInField(name: "PS", kind: .optional),
        ])
    }

    @Test func fieldsWithTheSameNameAndKindFillInTogether() {
        let template = FillInTemplate("Hi {fill:Name}, bye {fill:Name}. {fill:Name:multi}")
        #expect(template.fields.map(\.id) == ["fill:Name", "fill:multi:Name"])
        let values = FillInValues(text: ["fill:Name": "Ana", "fill:multi:Name": "A\nB"])
        #expect(MacroExpander().expand(template, values: values).text == "Hi Ana, bye Ana. A\nB")
    }

    @Test func choicesDefaultToTheFirstOption() {
        let template = FillInTemplate("Time: {choice:When:9:00|10:00}")
        #expect(template.fields.first?.options == ["9:00", "10:00"])
        #expect(MacroExpander().expand(template, values: FillInValues()).text == "Time: 9:00")
        #expect(template.defaultValues.text == ["choice:When": "9:00"])
        let picked = FillInValues(text: ["choice:When": "10:00"])
        #expect(MacroExpander().expand(template, values: picked).text == "Time: 10:00")
    }

    @Test func optionalSectionsCanBeLeftOut() {
        let template = FillInTemplate("Thanks{optional:Sign}\n{fill:Name}{optional:Title}, CEO{/optional}{/optional}!")
        #expect(template.fields.map(\.id) == ["optional:Sign", "fill:Name", "optional:Title"])
        let expander = MacroExpander()
        #expect(expander.expand(template, values: FillInValues(text: ["fill:Name": "Lu"])).text == "Thanks\nLu, CEO!")
        #expect(expander.expand(template, values: FillInValues(included: ["optional:Title": false])).text == "Thanks\n!")
        #expect(expander.expand(template, values: FillInValues(included: ["optional:Sign": false])).text == "Thanks!")
    }

    @Test func malformedTagsStayAsTyped() {
        let content = "{fill:} {choice:NoOptions} {optional:Open}x {/optional}{/optional} {{fill:A} {fill:B"
        let template = FillInTemplate(content)
        #expect(template.fields.map(\.id) == ["optional:Open", "fill:A"])
        let text = MacroExpander().expand(template, values: FillInValues(text: ["fill:A": "a"])).text
        #expect(text == "{fill:} {choice:NoOptions} x {/optional} {a {fill:B")

        let unclosed = FillInTemplate("a{optional:X}b{fill:C}")
        #expect(unclosed.fields.map(\.id) == ["fill:C"])
        #expect(MacroExpander().expand(unclosed, values: FillInValues()).text == "a{optional:X}b")
    }

    @Test func enteredValuesAreInsertedLiterally() {
        let template = FillInTemplate("{fill:X} on {isodate}")
        let expander = MacroExpander(now: Date(timeIntervalSince1970: 1_792_539_000), timeZone: TimeZone(identifier: "UTC")!)
        let result = expander.expand(template, values: FillInValues(text: ["fill:X": "{date} {cursor}"]))
        #expect(result == ExpansionResult(text: "{date} {cursor} on 2026-10-20", cursorOffsetFromEnd: 0))
    }

    @Test func cursorWorksAroundFields() {
        let template = FillInTemplate("Dear {fill:Name}, {cursor}{optional:PS}PS {fill:Name}{/optional}")
        let values = FillInValues(text: ["fill:Name": "Bo"])
        #expect(MacroExpander().expand(template, values: values) == ExpansionResult(text: "Dear Bo, PS Bo", cursorOffsetFromEnd: 5))

        let inSection = FillInTemplate("a{optional:S}{cursor}b{/optional}c{cursor}d")
        #expect(MacroExpander().expand(inSection, values: FillInValues()) == ExpansionResult(text: "abcd", cursorOffsetFromEnd: 3))
        let dropped = FillInValues(included: ["optional:S": false])
        #expect(MacroExpander().expand(inSection, values: dropped) == ExpansionResult(text: "acd", cursorOffsetFromEnd: 1))
    }
}

@Suite struct PromptBankTests {
    let bank = [
        Snippet(abbreviation: ";sig", content: "Cheers,\nLucas", label: "Sign-off"),
        Snippet(abbreviation: "", content: "\n  Review this code for bugs\nand edge cases"),
        Snippet(abbreviation: "", content: "Summarise this article", label: "Summary"),
        Snippet(abbreviation: "", content: "Hidden", label: "Off", isEnabled: false),
        Snippet(abbreviation: "", content: "", label: "Empty draft"),
    ]

    @Test func entriesAreEnabledSnippetsWithoutAbbreviation() {
        #expect(PromptBank.entries(in: bank).map(\.label) == ["", "Summary"])
    }

    @Test func titleIsLabelOrFirstNonEmptyLine() {
        #expect(PromptBank.title(of: bank[0]) == "Sign-off")
        #expect(PromptBank.title(of: bank[1]) == "Review this code for bugs")
        #expect(PromptBank.title(of: Snippet(abbreviation: ";x", content: "  \n")) == ";x")
    }

    @Test func emptyQueryListsBankFirstThenShortcuts() {
        let titles = PromptBank.search(bank, for: "").map(PromptBank.title(of:))
        #expect(titles == ["Review this code for bugs", "Summary", "Sign-off"])
    }

    @Test func ranksTitlePrefixThenContainsThenContent() {
        let snippets = [
            Snippet(abbreviation: "", content: "mentions code review here", label: "Notes"),
            Snippet(abbreviation: "", content: "x", label: "Quick review"),
            Snippet(abbreviation: "", content: "y", label: "Review PR"),
        ]
        let labels = PromptBank.search(snippets, for: " review ").map(\.label)
        #expect(labels == ["Review PR", "Quick review", "Notes"])
    }

    @Test func matchesAbbreviationsAndSkipsDisabled() {
        #expect(PromptBank.search(bank, for: ";si").map(\.label) == ["Sign-off"])
        #expect(PromptBank.search(bank, for: "hidden").isEmpty)
        #expect(PromptBank.search(bank, for: "zzz").isEmpty)
    }
}

@Suite struct TemplateVariableTests {
    let now = Date(timeIntervalSince1970: 1_792_539_000)
    let utc = TimeZone(identifier: "UTC")!

    @Test func bareNamesAreAskedFor() {
        let template = FillInTemplate("Hi {Client Name}, re {project_2}. {fill:Client Name}")
        #expect(template.fields == [
            FillInField(name: "Client Name", kind: .text),
            FillInField(name: "project_2", kind: .text),
        ])
        let values = FillInValues(text: ["fill:Client Name": "Ana", "fill:project_2": "Atlas"])
        #expect(MacroExpander().expand(template, values: values).text == "Hi Ana, re Atlas. Ana")
    }

    @Test func builtInsAndVariablesAreNotAskedFor() {
        let template = FillInTemplate("{date} {cursor} {company} {who}", variableNames: ["company"])
        #expect(template.fields.map(\.name) == ["who"])
    }

    @Test func codeLikeBracesStayAsTyped() {
        let template = FillInTemplate("${x} { return y } {2fast} {a.b} {}")
        #expect(template.fields.isEmpty)
    }

    @Test func variablesAreFilledInLiterally() {
        let expander = MacroExpander(now: now, clipboard: "clip", variables: ["company": "Acme {date}", "me": "Lucas"], timeZone: utc)
        let result = expander.expand("{me} at {company} on {isodate}, {clipboard}, {nobody}")
        #expect(result.text == "Lucas at Acme {date} on 2026-10-20, clip, ")
    }

    @Test func variablesWorkInsideOptionalSectionsAndAroundCursor() {
        let expander = MacroExpander(variables: ["sig": "L"])
        let template = FillInTemplate("Hi{cursor}{optional:Sign}\n{sig}{/optional}", variableNames: ["sig"])
        #expect(expander.expand(template, values: FillInValues()) == ExpansionResult(text: "Hi\nL", cursorOffsetFromEnd: 2))
        let dropped = FillInValues(included: ["optional:Sign": false])
        #expect(expander.expand(template, values: dropped) == ExpansionResult(text: "Hi", cursorOffsetFromEnd: 0))
    }

    @Test func variableNameProblems() {
        #expect(Variable(name: "company", value: "").nameProblem == nil)
        #expect(Variable(name: "my email", value: "").nameProblem == nil)
        #expect(Variable(name: "", value: "").nameProblem != nil)
        #expect(Variable(name: "date", value: "").nameProblem != nil)
        #expect(Variable(name: "a.b", value: "").nameProblem != nil)
    }

    @Test func lookupSkipsBadNamesAndKeepsTheFirstDuplicate() {
        let lookup = Variable.lookup([
            Variable(name: "x", value: "1"),
            Variable(name: "x", value: "2"),
            Variable(name: "date", value: "no"),
        ])
        #expect(lookup == ["x": "1"])
    }
}

@Suite struct SampleTests {
    @Test func templateSamplesAskOnlyForWhatIsNotAVariable() {
        let variableNames = Set(Variable.lookup(Variable.samples).keys)
        #expect(variableNames == ["my name", "company"])
        let asked = Snippet.samples
            .filter { $0.label.hasSuffix("(template)") }
            .map { FillInTemplate($0.content, variableNames: variableNames).fields.map(\.name) }
        #expect(asked == [["Client Name", "Day", "project"], ["Client Name", "project"]])
    }
}
