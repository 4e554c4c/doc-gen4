/-
Copyright (c) 2022 Henrik Böving. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Henrik Böving, Xubai Wang
-/
import DocGen4.Output.Base
import DocGen4.Output.ToHtmlFormat
import DocGen4.LeanInk.Process
import Lean.Data.Json
import LeanInk.Annotation.Alectryon

namespace LeanInk.Annotation.Alectryon

open DocGen4 Output
open scoped DocGen4.Jsx

structure AlectryonContext where
  counter : Nat

abbrev AlectryonM := StateT AlectryonContext HtmlM

def getNextButtonLabel : AlectryonM String := do
  let val ← get
  let newCounter := val.counter + 1
  set { val with counter := newCounter }
  pure s!"plain-lean4-lean-chk{val.counter}"

def TypeInfo.toHtml : TypeInfo → AlectryonM Html := sorry

def Token.toHtml (t : Token) : AlectryonM Html := do
  -- TODO: Show rest of token
  pure $ Html.text t.raw

def Contents.toHtml : Contents → AlectryonM (Array Html)
  | .string value => pure #[Html.text value]
  | .experimentalTokens values => values.mapM Token.toHtml

def Hypothesis.toHtml (h : Hypothesis) : AlectryonM Html := do
  let mut hypParts := #[<var>[h.names.intersperse ", " |>.map Html.text |>.toArray]<//var>]
  if h.body != "" then
    hypParts := hypParts.push
      <span class="hyp-body">
        <b>:= <//b>
        <span>{h.body}<//span>
      <//span>
  hypParts := hypParts.push
      <span class="hyp-type">
        <b>: <//b>
        <span >{h.type}<//span>
      <//span>

  pure
    <span>
      [hypParts]
    <//span>

def Goal.toHtml (g : Goal) : AlectryonM Html := do
  let mut hypotheses := #[]
  for hyp in g.hypotheses do
    let rendered ← hyp.toHtml
    hypotheses := hypotheses.push rendered
    hypotheses := hypotheses.push <br/>
  pure
    <blockquote class="alectryon-goal">
      <div class="goal-hyps">
        [hypotheses]
      <//div>
      <span class="goal-separator">
        <hr><span class="goal-name">{g.name}<//span><//hr>
      <//span>
      <div class="goal-conclusion">
        {g.conclusion}
      <//div>
    <//blockquote>

def Message.toHtml (m : Message) : AlectryonM Html := do
  pure
    <blockquote class="alectryon-message">
      -- TODO: This might have to be done in a fancier way
      {m.contents}
    <//blockquote>

def Sentence.toHtml (s : Sentence) : AlectryonM Html := do
  let messages :=
    if s.messages.size > 0 then
      #[
        <div class="alectryon-messages">
          [←s.messages.mapM Message.toHtml]
        <//div>
      ]
    else
      #[]
  
  let goals :=
    if s.goals.size > 0 then
      -- TODO: Alectryon has a "alectryon-extra-goals" here, implement it
      #[
        <div class="alectryon-goals">
          [←s.goals.mapM Goal.toHtml]
        <//div>
      ]
    else
      #[]

  let buttonLabel ← getNextButtonLabel

  pure
    <span class="alectryon-sentence">
      <input class="alectryon-toggle" id={buttonLabel} style="display: none" type="checkbox"/>
      <label class="alectryon-input" for={buttonLabel}>
        [←s.contents.toHtml]
      <//label>
      <small class="alectryon-output">
        [messages]
        [goals]
      <//small>
    <//span>

def Text.toHtml (t : Text) : AlectryonM Html := do
  pure
    <span class="alectryon-wsp">
      [←t.contents.toHtml]
    <//span>

def Fragment.toHtml : Fragment → AlectryonM Html
  | .text value => value.toHtml
  | .sentence value => value.toHtml

def baseHtml (content : Array Html) : AlectryonM Html := do
  let banner :=
    <div «class»="alectryon-banner">
      Built with <a href="https://github.com/leanprover/doc-gen4">doc-gen4<//a>, running Lean4.
      Bubbles (<span class="alectryon-bubble"><//span>) indicate interactive fragments: hover for details, tap to reveal contents.
      Use <kbd>Ctrl+↑<//kbd> <kbd>Ctrl+↓<//kbd> to navigate, <kbd>Ctrl+🖱️<//kbd> to focus.
      On Mac, use <kbd>Cmd<//kbd> instead of <kbd>Ctrl<//kbd>.
    </div>

  pure
    <html lang="en" class="alectryon-standalone">
      <head>
        <meta charset="UTF-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>

        <link rel="stylesheet" href={s!"{←getRoot}src/alectryon.css"}/>
        <link rel="stylesheet" href={s!"{←getRoot}src/docutils_basic.css"}/>
        <link rel="shortcut icon" href={s!"{←getRoot}favicon.ico"}/>

        <script defer="true" src={s!"{←getRoot}src/alectryon.js"}></script>
      </head>
      <body>
        <article class="alectryon-root alectryon-centered">
          {banner}
          <pre class="alectryon-io highlight">
            [content]
          </pre>
        </article>
      </body>
    </html>

def renderFragments (fs : Array Fragment) : AlectryonM Html :=
  fs.mapM Fragment.toHtml >>= baseHtml

end LeanInk.Annotation.Alectryon

namespace DocGen4.Output.LeanInk

open Lean
open LeanInk.Annotation.Alectryon
open scoped DocGen4.Jsx

def moduleToHtml (module : Process.Module) (inkPath : System.FilePath) (sourceFilePath : System.FilePath) : HtmlT IO Html := withReader (setCurrentName module.name) do
  let json ← runInk inkPath sourceFilePath
  let fragments := fromJson? json
  match fragments with
  | .ok fragments =>
    let render := StateT.run (LeanInk.Annotation.Alectryon.renderFragments fragments) { counter := 0 }
    let ctx ← read
    let (html, _) := ReaderT.run render ctx
    pure html
  | .error err => throw $ IO.userError s!"Error while parsing LeanInk Output: {err}"

end DocGen4.Output.LeanInk
