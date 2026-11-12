// ==UserScript==
// @name         Duality Client Reborn (compatibility preview)
// @namespace    arena.survev.reborn
// @version      0.3.0
// @description  Lightweight menu, validated semantic discovery, bounded hooks and reversible features. Live compatibility unverified.
// @match        https://survev.io/*
// @match        https://*.survev.io/*
// @run-at       document-start
// @grant        none
// @inject-into  page
// @sandbox      raw
// @noframes
// ==/UserScript==
/*! Bundled parser: Acorn.
MIT License

Copyright (C) 2012-2022 by various contributors (see AUTHORS)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/
(() => {
  var __defProp = Object.defineProperty;
  var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

  // node_modules/acorn/dist/acorn.mjs
  var astralIdentifierCodes = [509, 0, 227, 0, 150, 4, 294, 9, 1368, 2, 2, 1, 6, 3, 41, 2, 5, 0, 166, 1, 574, 3, 9, 9, 7, 9, 32, 4, 318, 1, 80, 3, 71, 10, 50, 3, 123, 2, 54, 14, 32, 10, 3, 1, 11, 3, 46, 10, 8, 0, 46, 9, 7, 2, 37, 13, 2, 9, 6, 1, 45, 0, 13, 2, 49, 13, 9, 3, 2, 11, 83, 11, 7, 0, 3, 0, 158, 11, 6, 9, 7, 3, 56, 1, 2, 6, 3, 1, 3, 2, 10, 0, 11, 1, 3, 6, 4, 4, 68, 8, 2, 0, 3, 0, 2, 3, 2, 4, 2, 0, 15, 1, 83, 17, 10, 9, 5, 0, 82, 19, 13, 9, 214, 6, 3, 8, 28, 1, 83, 16, 16, 9, 82, 12, 9, 9, 7, 19, 58, 14, 5, 9, 243, 14, 166, 9, 71, 5, 2, 1, 3, 3, 2, 0, 2, 1, 13, 9, 120, 6, 3, 6, 4, 0, 29, 9, 41, 6, 2, 3, 9, 0, 10, 10, 47, 15, 343, 9, 54, 7, 2, 7, 17, 9, 57, 21, 2, 13, 123, 5, 4, 0, 2, 1, 2, 6, 2, 0, 9, 9, 49, 4, 2, 1, 2, 4, 9, 9, 330, 3, 10, 1, 2, 0, 49, 6, 4, 4, 14, 10, 5350, 0, 7, 14, 11465, 27, 2343, 9, 87, 9, 39, 4, 60, 6, 26, 9, 535, 9, 470, 0, 2, 54, 8, 3, 82, 0, 12, 1, 19628, 1, 4178, 9, 519, 45, 3, 22, 543, 4, 4, 5, 9, 7, 3, 6, 31, 3, 149, 2, 1418, 49, 513, 54, 5, 49, 9, 0, 15, 0, 23, 4, 2, 14, 1361, 6, 2, 16, 3, 6, 2, 1, 2, 4, 101, 0, 161, 6, 10, 9, 357, 0, 62, 13, 499, 13, 245, 1, 2, 9, 726, 6, 110, 6, 6, 9, 4759, 9, 787719, 239];
  var astralIdentifierStartCodes = [0, 11, 2, 25, 2, 18, 2, 1, 2, 14, 3, 13, 35, 122, 70, 52, 268, 28, 4, 48, 48, 31, 14, 29, 6, 37, 11, 29, 3, 35, 5, 7, 2, 4, 43, 157, 19, 35, 5, 35, 5, 39, 9, 51, 13, 10, 2, 14, 2, 6, 2, 1, 2, 10, 2, 14, 2, 6, 2, 1, 4, 51, 13, 310, 10, 21, 11, 7, 25, 5, 2, 41, 2, 8, 70, 5, 3, 0, 2, 43, 2, 1, 4, 0, 3, 22, 11, 22, 10, 30, 66, 18, 2, 1, 11, 21, 11, 25, 71, 55, 7, 1, 65, 0, 16, 3, 2, 2, 2, 28, 43, 28, 4, 28, 36, 7, 2, 27, 28, 53, 11, 21, 11, 18, 14, 17, 111, 72, 56, 50, 14, 50, 14, 35, 39, 27, 10, 22, 251, 41, 7, 1, 17, 2, 60, 28, 11, 0, 9, 21, 43, 17, 47, 20, 28, 22, 13, 52, 58, 1, 3, 0, 14, 44, 33, 24, 27, 35, 30, 0, 3, 0, 9, 34, 4, 0, 13, 47, 15, 3, 22, 0, 2, 0, 36, 17, 2, 24, 20, 1, 64, 6, 2, 0, 2, 3, 2, 14, 2, 9, 8, 46, 39, 7, 3, 1, 3, 21, 2, 6, 2, 1, 2, 4, 4, 0, 19, 0, 13, 4, 31, 9, 2, 0, 3, 0, 2, 37, 2, 0, 26, 0, 2, 0, 45, 52, 19, 3, 21, 2, 31, 47, 21, 1, 2, 0, 185, 46, 42, 3, 37, 47, 21, 0, 60, 42, 14, 0, 72, 26, 38, 6, 186, 43, 117, 63, 32, 7, 3, 0, 3, 7, 2, 1, 2, 23, 16, 0, 2, 0, 95, 7, 3, 38, 17, 0, 2, 0, 29, 0, 11, 39, 8, 0, 22, 0, 12, 45, 20, 0, 19, 72, 200, 32, 32, 8, 2, 36, 18, 0, 50, 29, 113, 6, 2, 1, 2, 37, 22, 0, 26, 5, 2, 1, 2, 31, 15, 0, 328, 18, 16, 0, 2, 12, 2, 33, 125, 0, 80, 921, 103, 110, 18, 195, 2637, 96, 16, 1071, 18, 5, 26, 3994, 6, 582, 6842, 29, 1763, 568, 8, 30, 18, 78, 18, 29, 19, 47, 17, 3, 32, 20, 6, 18, 433, 44, 212, 63, 129, 74, 6, 0, 67, 12, 65, 1, 2, 0, 29, 6135, 9, 1237, 42, 9, 8936, 3, 2, 6, 2, 1, 2, 290, 16, 0, 30, 2, 3, 0, 15, 3, 9, 395, 2309, 106, 6, 12, 4, 8, 8, 9, 5991, 84, 2, 70, 2, 1, 3, 0, 3, 1, 3, 3, 2, 11, 2, 0, 2, 6, 2, 64, 2, 3, 3, 7, 2, 6, 2, 27, 2, 3, 2, 4, 2, 0, 4, 6, 2, 339, 3, 24, 2, 24, 2, 30, 2, 24, 2, 30, 2, 24, 2, 30, 2, 24, 2, 30, 2, 24, 2, 7, 1845, 30, 7, 5, 262, 61, 147, 44, 11, 6, 17, 0, 322, 29, 19, 43, 485, 27, 229, 29, 3, 0, 496, 6, 2, 3, 2, 1, 2, 14, 2, 196, 60, 67, 8, 0, 1205, 3, 2, 26, 2, 1, 2, 0, 3, 0, 2, 9, 2, 3, 2, 0, 2, 0, 7, 0, 5, 0, 2, 0, 2, 0, 2, 2, 2, 1, 2, 0, 3, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 1, 2, 0, 3, 3, 2, 6, 2, 3, 2, 3, 2, 0, 2, 9, 2, 16, 6, 2, 2, 4, 2, 16, 4421, 42719, 33, 4153, 7, 221, 3, 5761, 15, 7472, 16, 621, 2467, 541, 1507, 4938, 6, 4191];
  var nonASCIIidentifierChars = "‌‍·̀-ͯ·҃-֑҇-ׇֽֿׁׂׅׄؐ-ًؚ-٩ٰۖ-ۜ۟-۪ۤۧۨ-ۭ۰-۹ܑܰ-݊ަ-ް߀-߉߫-߽߳ࠖ-࠙ࠛ-ࠣࠥ-ࠧࠩ-࡙࠭-࡛ࢗ-࢟࣊-ࣣ࣡-ःऺ-़ा-ॏ॑-ॗॢॣ०-९ঁ-ঃ়া-ৄেৈো-্ৗৢৣ০-৯৾ਁ-ਃ਼ਾ-ੂੇੈੋ-੍ੑ੦-ੱੵઁ-ઃ઼ા-ૅે-ૉો-્ૢૣ૦-૯ૺ-૿ଁ-ଃ଼ା-ୄେୈୋ-୍୕-ୗୢୣ୦-୯ஂா-ூெ-ைொ-்ௗ௦-௯ఀ-ఄ఼ా-ౄె-ైొ-్ౕౖౢౣ౦-౯ಁ-ಃ಼ಾ-ೄೆ-ೈೊ-್ೕೖೢೣ೦-೯ೳഀ-ഃ഻഼ാ-ൄെ-ൈൊ-്ൗൢൣ൦-൯ඁ-ඃ්ා-ුූෘ-ෟ෦-෯ෲෳัิ-ฺ็-๎๐-๙ັິ-ຼ່-໎໐-໙༘༙༠-༩༹༵༷༾༿ཱ-྄྆྇ྍ-ྗྙ-ྼ࿆ါ-ှ၀-၉ၖ-ၙၞ-ၠၢ-ၤၧ-ၭၱ-ၴႂ-ႍႏ-ႝ፝-፟፩-፱ᜒ-᜕ᜲ-᜴ᝒᝓᝲᝳ឴-៓៝០-៩᠋-᠍᠏-᠙ᢩᤠ-ᤫᤰ-᤻᥆-᥏᧐-᧚ᨗ-ᨛᩕ-ᩞ᩠-᩿᩼-᪉᪐-᪙᪰-᪽ᪿ-ᫎᬀ-ᬄ᬴-᭄᭐-᭙᭫-᭳ᮀ-ᮂᮡ-ᮭ᮰-᮹᯦-᯳ᰤ-᰷᱀-᱉᱐-᱙᳐-᳔᳒-᳨᳭᳴᳷-᳹᷀-᷿‌‍‿⁀⁔⃐-⃥⃜⃡-⃰⳯-⵿⳱ⷠ-〪ⷿ-゙゚〯・꘠-꘩꙯ꙴ-꙽ꚞꚟ꛰꛱ꠂ꠆ꠋꠣ-ꠧ꠬ꢀꢁꢴ-ꣅ꣐-꣙꣠-꣱ꣿ-꤉ꤦ-꤭ꥇ-꥓ꦀ-ꦃ꦳-꧀꧐-꧙ꧥ꧰-꧹ꨩ-ꨶꩃꩌꩍ꩐-꩙ꩻ-ꩽꪰꪲ-ꪴꪷꪸꪾ꪿꫁ꫫ-ꫯꫵ꫶ꯣ-ꯪ꯬꯭꯰-꯹ﬞ︀-️︠-︯︳︴﹍-﹏０-９＿･";
  var nonASCIIidentifierStartChars = "ªµºÀ-ÖØ-öø-ˁˆ-ˑˠ-ˤˬˮͰ-ʹͶͷͺ-ͽͿΆΈ-ΊΌΎ-ΡΣ-ϵϷ-ҁҊ-ԯԱ-Ֆՙՠ-ֈא-תׯ-ײؠ-يٮٯٱ-ۓەۥۦۮۯۺ-ۼۿܐܒ-ܯݍ-ޥޱߊ-ߪߴߵߺࠀ-ࠕࠚࠤࠨࡀ-ࡘࡠ-ࡪࡰ-ࢇࢉ-ࢎࢠ-ࣉऄ-हऽॐक़-ॡॱ-ঀঅ-ঌএঐও-নপ-রলশ-হঽৎড়ঢ়য়-ৡৰৱৼਅ-ਊਏਐਓ-ਨਪ-ਰਲਲ਼ਵਸ਼ਸਹਖ਼-ੜਫ਼ੲ-ੴઅ-ઍએ-ઑઓ-નપ-રલળવ-હઽૐૠૡૹଅ-ଌଏଐଓ-ନପ-ରଲଳଵ-ହଽଡ଼ଢ଼ୟ-ୡୱஃஅ-ஊஎ-ஐஒ-கஙசஜஞடணதந-பம-ஹௐఅ-ఌఎ-ఐఒ-నప-హఽౘ-ౚౝౠౡಀಅ-ಌಎ-ಐಒ-ನಪ-ಳವ-ಹಽೝೞೠೡೱೲഄ-ഌഎ-ഐഒ-ഺഽൎൔ-ൖൟ-ൡൺ-ൿඅ-ඖක-නඳ-රලව-ෆก-ะาำเ-ๆກຂຄຆ-ຊຌ-ຣລວ-ະາຳຽເ-ໄໆໜ-ໟༀཀ-ཇཉ-ཬྈ-ྌက-ဪဿၐ-ၕၚ-ၝၡၥၦၮ-ၰၵ-ႁႎႠ-ჅჇჍა-ჺჼ-ቈቊ-ቍቐ-ቖቘቚ-ቝበ-ኈኊ-ኍነ-ኰኲ-ኵኸ-ኾዀዂ-ዅወ-ዖዘ-ጐጒ-ጕጘ-ፚᎀ-ᎏᎠ-Ᏽᏸ-ᏽᐁ-ᙬᙯ-ᙿᚁ-ᚚᚠ-ᛪᛮ-ᛸᜀ-ᜑᜟ-ᜱᝀ-ᝑᝠ-ᝬᝮ-ᝰក-ឳៗៜᠠ-ᡸᢀ-ᢨᢪᢰ-ᣵᤀ-ᤞᥐ-ᥭᥰ-ᥴᦀ-ᦫᦰ-ᧉᨀ-ᨖᨠ-ᩔᪧᬅ-ᬳᭅ-ᭌᮃ-ᮠᮮᮯᮺ-ᯥᰀ-ᰣᱍ-ᱏᱚ-ᱽᲀ-ᲊᲐ-ᲺᲽ-Ჿᳩ-ᳬᳮ-ᳳᳵᳶᳺᴀ-ᶿḀ-ἕἘ-Ἕἠ-ὅὈ-Ὅὐ-ὗὙὛὝὟ-ώᾀ-ᾴᾶ-ᾼιῂ-ῄῆ-ῌῐ-ΐῖ-Ίῠ-Ῥῲ-ῴῶ-ῼⁱⁿₐ-ₜℂℇℊ-ℓℕ℘-ℝℤΩℨK-ℹℼ-ℿⅅ-ⅉⅎⅠ-ↈⰀ-ⳤⳫ-ⳮⳲⳳⴀ-ⴥⴧⴭⴰ-ⵧⵯⶀ-ⶖⶠ-ⶦⶨ-ⶮⶰ-ⶶⶸ-ⶾⷀ-ⷆⷈ-ⷎⷐ-ⷖⷘ-ⷞ々-〇〡-〩〱-〵〸-〼ぁ-ゖ゛-ゟァ-ヺー-ヿㄅ-ㄯㄱ-ㆎㆠ-ㆿㇰ-ㇿ㐀-䶿一-ꒌꓐ-ꓽꔀ-ꘌꘐ-ꘟꘪꘫꙀ-ꙮꙿ-ꚝꚠ-ꛯꜗ-ꜟꜢ-ꞈꞋ-ꟍꟐꟑꟓꟕ-Ƛꟲ-ꠁꠃ-ꠅꠇ-ꠊꠌ-ꠢꡀ-ꡳꢂ-ꢳꣲ-ꣷꣻꣽꣾꤊ-ꤥꤰ-ꥆꥠ-ꥼꦄ-ꦲꧏꧠ-ꧤꧦ-ꧯꧺ-ꧾꨀ-ꨨꩀ-ꩂꩄ-ꩋꩠ-ꩶꩺꩾ-ꪯꪱꪵꪶꪹ-ꪽꫀꫂꫛ-ꫝꫠ-ꫪꫲ-ꫴꬁ-ꬆꬉ-ꬎꬑ-ꬖꬠ-ꬦꬨ-ꬮꬰ-ꭚꭜ-ꭩꭰ-ꯢ가-힣ힰ-ퟆퟋ-ퟻ豈-舘並-龎ﬀ-ﬆﬓ-ﬗיִײַ-ﬨשׁ-זּטּ-לּמּנּסּףּפּצּ-ﮱﯓ-ﴽﵐ-ﶏﶒ-ﷇﷰ-ﷻﹰ-ﹴﹶ-ﻼＡ-Ｚａ-ｚｦ-ﾾￂ-ￇￊ-ￏￒ-ￗￚ-ￜ";
  var reservedWords = {
    3: "abstract boolean byte char class double enum export extends final float goto implements import int interface long native package private protected public short static super synchronized throws transient volatile",
    5: "class enum extends super const export import",
    6: "enum",
    strict: "implements interface let package private protected public static yield",
    strictBind: "eval arguments"
  };
  var ecma5AndLessKeywords = "break case catch continue debugger default do else finally for function if return switch throw try var while with null true false instanceof typeof void delete new in this";
  var keywords$1 = {
    5: ecma5AndLessKeywords,
    "5module": ecma5AndLessKeywords + " export import",
    6: ecma5AndLessKeywords + " const class extends export import super"
  };
  var keywordRelationalOperator = /^in(stanceof)?$/;
  var nonASCIIidentifierStart = new RegExp("[" + nonASCIIidentifierStartChars + "]");
  var nonASCIIidentifier = new RegExp("[" + nonASCIIidentifierStartChars + nonASCIIidentifierChars + "]");
  function isInAstralSet(code, set) {
    var pos = 65536;
    for (var i = 0; i < set.length; i += 2) {
      pos += set[i];
      if (pos > code) {
        return false;
      }
      pos += set[i + 1];
      if (pos >= code) {
        return true;
      }
    }
    return false;
  }
  __name(isInAstralSet, "isInAstralSet");
  function isIdentifierStart(code, astral) {
    if (code < 65) {
      return code === 36;
    }
    if (code < 91) {
      return true;
    }
    if (code < 97) {
      return code === 95;
    }
    if (code < 123) {
      return true;
    }
    if (code <= 65535) {
      return code >= 170 && nonASCIIidentifierStart.test(String.fromCharCode(code));
    }
    if (astral === false) {
      return false;
    }
    return isInAstralSet(code, astralIdentifierStartCodes);
  }
  __name(isIdentifierStart, "isIdentifierStart");
  function isIdentifierChar(code, astral) {
    if (code < 48) {
      return code === 36;
    }
    if (code < 58) {
      return true;
    }
    if (code < 65) {
      return false;
    }
    if (code < 91) {
      return true;
    }
    if (code < 97) {
      return code === 95;
    }
    if (code < 123) {
      return true;
    }
    if (code <= 65535) {
      return code >= 170 && nonASCIIidentifier.test(String.fromCharCode(code));
    }
    if (astral === false) {
      return false;
    }
    return isInAstralSet(code, astralIdentifierStartCodes) || isInAstralSet(code, astralIdentifierCodes);
  }
  __name(isIdentifierChar, "isIdentifierChar");
  var TokenType = /* @__PURE__ */ __name(function TokenType2(label, conf) {
    if (conf === void 0) conf = {};
    this.label = label;
    this.keyword = conf.keyword;
    this.beforeExpr = !!conf.beforeExpr;
    this.startsExpr = !!conf.startsExpr;
    this.isLoop = !!conf.isLoop;
    this.isAssign = !!conf.isAssign;
    this.prefix = !!conf.prefix;
    this.postfix = !!conf.postfix;
    this.binop = conf.binop || null;
    this.updateContext = null;
  }, "TokenType");
  function binop(name, prec) {
    return new TokenType(name, { beforeExpr: true, binop: prec });
  }
  __name(binop, "binop");
  var beforeExpr = { beforeExpr: true };
  var startsExpr = { startsExpr: true };
  var keywords = {};
  function kw(name, options) {
    if (options === void 0) options = {};
    options.keyword = name;
    return keywords[name] = new TokenType(name, options);
  }
  __name(kw, "kw");
  var types$1 = {
    num: new TokenType("num", startsExpr),
    regexp: new TokenType("regexp", startsExpr),
    string: new TokenType("string", startsExpr),
    name: new TokenType("name", startsExpr),
    privateId: new TokenType("privateId", startsExpr),
    eof: new TokenType("eof"),
    // Punctuation token types.
    bracketL: new TokenType("[", { beforeExpr: true, startsExpr: true }),
    bracketR: new TokenType("]"),
    braceL: new TokenType("{", { beforeExpr: true, startsExpr: true }),
    braceR: new TokenType("}"),
    parenL: new TokenType("(", { beforeExpr: true, startsExpr: true }),
    parenR: new TokenType(")"),
    comma: new TokenType(",", beforeExpr),
    semi: new TokenType(";", beforeExpr),
    colon: new TokenType(":", beforeExpr),
    dot: new TokenType("."),
    question: new TokenType("?", beforeExpr),
    questionDot: new TokenType("?."),
    arrow: new TokenType("=>", beforeExpr),
    template: new TokenType("template"),
    invalidTemplate: new TokenType("invalidTemplate"),
    ellipsis: new TokenType("...", beforeExpr),
    backQuote: new TokenType("`", startsExpr),
    dollarBraceL: new TokenType("${", { beforeExpr: true, startsExpr: true }),
    // Operators. These carry several kinds of properties to help the
    // parser use them properly (the presence of these properties is
    // what categorizes them as operators).
    //
    // `binop`, when present, specifies that this operator is a binary
    // operator, and will refer to its precedence.
    //
    // `prefix` and `postfix` mark the operator as a prefix or postfix
    // unary operator.
    //
    // `isAssign` marks all of `=`, `+=`, `-=` etcetera, which act as
    // binary operators with a very low precedence, that should result
    // in AssignmentExpression nodes.
    eq: new TokenType("=", { beforeExpr: true, isAssign: true }),
    assign: new TokenType("_=", { beforeExpr: true, isAssign: true }),
    incDec: new TokenType("++/--", { prefix: true, postfix: true, startsExpr: true }),
    prefix: new TokenType("!/~", { beforeExpr: true, prefix: true, startsExpr: true }),
    logicalOR: binop("||", 1),
    logicalAND: binop("&&", 2),
    bitwiseOR: binop("|", 3),
    bitwiseXOR: binop("^", 4),
    bitwiseAND: binop("&", 5),
    equality: binop("==/!=/===/!==", 6),
    relational: binop("</>/<=/>=", 7),
    bitShift: binop("<</>>/>>>", 8),
    plusMin: new TokenType("+/-", { beforeExpr: true, binop: 9, prefix: true, startsExpr: true }),
    modulo: binop("%", 10),
    star: binop("*", 10),
    slash: binop("/", 10),
    starstar: new TokenType("**", { beforeExpr: true }),
    coalesce: binop("??", 1),
    // Keyword token types.
    _break: kw("break"),
    _case: kw("case", beforeExpr),
    _catch: kw("catch"),
    _continue: kw("continue"),
    _debugger: kw("debugger"),
    _default: kw("default", beforeExpr),
    _do: kw("do", { isLoop: true, beforeExpr: true }),
    _else: kw("else", beforeExpr),
    _finally: kw("finally"),
    _for: kw("for", { isLoop: true }),
    _function: kw("function", startsExpr),
    _if: kw("if"),
    _return: kw("return", beforeExpr),
    _switch: kw("switch"),
    _throw: kw("throw", beforeExpr),
    _try: kw("try"),
    _var: kw("var"),
    _const: kw("const"),
    _while: kw("while", { isLoop: true }),
    _with: kw("with"),
    _new: kw("new", { beforeExpr: true, startsExpr: true }),
    _this: kw("this", startsExpr),
    _super: kw("super", startsExpr),
    _class: kw("class", startsExpr),
    _extends: kw("extends", beforeExpr),
    _export: kw("export"),
    _import: kw("import", startsExpr),
    _null: kw("null", startsExpr),
    _true: kw("true", startsExpr),
    _false: kw("false", startsExpr),
    _in: kw("in", { beforeExpr: true, binop: 7 }),
    _instanceof: kw("instanceof", { beforeExpr: true, binop: 7 }),
    _typeof: kw("typeof", { beforeExpr: true, prefix: true, startsExpr: true }),
    _void: kw("void", { beforeExpr: true, prefix: true, startsExpr: true }),
    _delete: kw("delete", { beforeExpr: true, prefix: true, startsExpr: true })
  };
  var lineBreak = /\r\n?|\n|\u2028|\u2029/;
  var lineBreakG = new RegExp(lineBreak.source, "g");
  function isNewLine(code) {
    return code === 10 || code === 13 || code === 8232 || code === 8233;
  }
  __name(isNewLine, "isNewLine");
  function nextLineBreak(code, from, end) {
    if (end === void 0) end = code.length;
    for (var i = from; i < end; i++) {
      var next = code.charCodeAt(i);
      if (isNewLine(next)) {
        return i < end - 1 && next === 13 && code.charCodeAt(i + 1) === 10 ? i + 2 : i + 1;
      }
    }
    return -1;
  }
  __name(nextLineBreak, "nextLineBreak");
  var nonASCIIwhitespace = /[\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]/;
  var skipWhiteSpace = /(?:\s|\/\/.*|\/\*[^]*?\*\/)*/g;
  var ref = Object.prototype;
  var hasOwnProperty = ref.hasOwnProperty;
  var toString = ref.toString;
  var hasOwn = Object.hasOwn || (function(obj, propName) {
    return hasOwnProperty.call(obj, propName);
  });
  var isArray = Array.isArray || (function(obj) {
    return toString.call(obj) === "[object Array]";
  });
  var regexpCache = /* @__PURE__ */ Object.create(null);
  function wordsRegexp(words) {
    return regexpCache[words] || (regexpCache[words] = new RegExp("^(?:" + words.replace(/ /g, "|") + ")$"));
  }
  __name(wordsRegexp, "wordsRegexp");
  function codePointToString(code) {
    if (code <= 65535) {
      return String.fromCharCode(code);
    }
    code -= 65536;
    return String.fromCharCode((code >> 10) + 55296, (code & 1023) + 56320);
  }
  __name(codePointToString, "codePointToString");
  var loneSurrogate = /(?:[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF])/;
  var Position = /* @__PURE__ */ __name(function Position2(line, col) {
    this.line = line;
    this.column = col;
  }, "Position");
  Position.prototype.offset = /* @__PURE__ */ __name(function offset(n) {
    return new Position(this.line, this.column + n);
  }, "offset");
  var SourceLocation = /* @__PURE__ */ __name(function SourceLocation2(p, start2, end) {
    this.start = start2;
    this.end = end;
    if (p.sourceFile !== null) {
      this.source = p.sourceFile;
    }
  }, "SourceLocation");
  function getLineInfo(input, offset2) {
    for (var line = 1, cur = 0; ; ) {
      var nextBreak = nextLineBreak(input, cur, offset2);
      if (nextBreak < 0) {
        return new Position(line, offset2 - cur);
      }
      ++line;
      cur = nextBreak;
    }
  }
  __name(getLineInfo, "getLineInfo");
  var defaultOptions = {
    // `ecmaVersion` indicates the ECMAScript version to parse. Must be
    // either 3, 5, 6 (or 2015), 7 (2016), 8 (2017), 9 (2018), 10
    // (2019), 11 (2020), 12 (2021), 13 (2022), 14 (2023), or `"latest"`
    // (the latest version the library supports). This influences
    // support for strict mode, the set of reserved words, and support
    // for new syntax features.
    ecmaVersion: null,
    // `sourceType` indicates the mode the code should be parsed in.
    // Can be either `"script"` or `"module"`. This influences global
    // strict mode and parsing of `import` and `export` declarations.
    sourceType: "script",
    // `onInsertedSemicolon` can be a callback that will be called when
    // a semicolon is automatically inserted. It will be passed the
    // position of the inserted semicolon as an offset, and if
    // `locations` is enabled, it is given the location as a `{line,
    // column}` object as second argument.
    onInsertedSemicolon: null,
    // `onTrailingComma` is similar to `onInsertedSemicolon`, but for
    // trailing commas.
    onTrailingComma: null,
    // By default, reserved words are only enforced if ecmaVersion >= 5.
    // Set `allowReserved` to a boolean value to explicitly turn this on
    // an off. When this option has the value "never", reserved words
    // and keywords can also not be used as property names.
    allowReserved: null,
    // When enabled, a return at the top level is not considered an
    // error.
    allowReturnOutsideFunction: false,
    // When enabled, import/export statements are not constrained to
    // appearing at the top of the program, and an import.meta expression
    // in a script isn't considered an error.
    allowImportExportEverywhere: false,
    // By default, await identifiers are allowed to appear at the top-level scope only if ecmaVersion >= 2022.
    // When enabled, await identifiers are allowed to appear at the top-level scope,
    // but they are still not allowed in non-async functions.
    allowAwaitOutsideFunction: null,
    // When enabled, super identifiers are not constrained to
    // appearing in methods and do not raise an error when they appear elsewhere.
    allowSuperOutsideMethod: null,
    // When enabled, hashbang directive in the beginning of file is
    // allowed and treated as a line comment. Enabled by default when
    // `ecmaVersion` >= 2023.
    allowHashBang: false,
    // By default, the parser will verify that private properties are
    // only used in places where they are valid and have been declared.
    // Set this to false to turn such checks off.
    checkPrivateFields: true,
    // When `locations` is on, `loc` properties holding objects with
    // `start` and `end` properties in `{line, column}` form (with
    // line being 1-based and column 0-based) will be attached to the
    // nodes.
    locations: false,
    // A function can be passed as `onToken` option, which will
    // cause Acorn to call that function with object in the same
    // format as tokens returned from `tokenizer().getToken()`. Note
    // that you are not allowed to call the parser from the
    // callback—that will corrupt its internal state.
    onToken: null,
    // A function can be passed as `onComment` option, which will
    // cause Acorn to call that function with `(block, text, start,
    // end)` parameters whenever a comment is skipped. `block` is a
    // boolean indicating whether this is a block (`/* */`) comment,
    // `text` is the content of the comment, and `start` and `end` are
    // character offsets that denote the start and end of the comment.
    // When the `locations` option is on, two more parameters are
    // passed, the full `{line, column}` locations of the start and
    // end of the comments. Note that you are not allowed to call the
    // parser from the callback—that will corrupt its internal state.
    // When this option has an array as value, objects representing the
    // comments are pushed to it.
    onComment: null,
    // Nodes have their start and end characters offsets recorded in
    // `start` and `end` properties (directly on the node, rather than
    // the `loc` object, which holds line/column data. To also add a
    // [semi-standardized][range] `range` property holding a `[start,
    // end]` array with the same numbers, set the `ranges` option to
    // `true`.
    //
    // [range]: https://bugzilla.mozilla.org/show_bug.cgi?id=745678
    ranges: false,
    // It is possible to parse multiple files into a single AST by
    // passing the tree produced by parsing the first file as
    // `program` option in subsequent parses. This will add the
    // toplevel forms of the parsed file to the `Program` (top) node
    // of an existing parse tree.
    program: null,
    // When `locations` is on, you can pass this to record the source
    // file in every node's `loc` object.
    sourceFile: null,
    // This value, if given, is stored in every node, whether
    // `locations` is on or off.
    directSourceFile: null,
    // When enabled, parenthesized expressions are represented by
    // (non-standard) ParenthesizedExpression nodes
    preserveParens: false
  };
  var warnedAboutEcmaVersion = false;
  function getOptions(opts) {
    var options = {};
    for (var opt in defaultOptions) {
      options[opt] = opts && hasOwn(opts, opt) ? opts[opt] : defaultOptions[opt];
    }
    if (options.ecmaVersion === "latest") {
      options.ecmaVersion = 1e8;
    } else if (options.ecmaVersion == null) {
      if (!warnedAboutEcmaVersion && typeof console === "object" && console.warn) {
        warnedAboutEcmaVersion = true;
        console.warn("Since Acorn 8.0.0, options.ecmaVersion is required.\nDefaulting to 2020, but this will stop working in the future.");
      }
      options.ecmaVersion = 11;
    } else if (options.ecmaVersion >= 2015) {
      options.ecmaVersion -= 2009;
    }
    if (options.allowReserved == null) {
      options.allowReserved = options.ecmaVersion < 5;
    }
    if (!opts || opts.allowHashBang == null) {
      options.allowHashBang = options.ecmaVersion >= 14;
    }
    if (isArray(options.onToken)) {
      var tokens = options.onToken;
      options.onToken = function(token) {
        return tokens.push(token);
      };
    }
    if (isArray(options.onComment)) {
      options.onComment = pushComment(options, options.onComment);
    }
    return options;
  }
  __name(getOptions, "getOptions");
  function pushComment(options, array) {
    return function(block, text, start2, end, startLoc, endLoc) {
      var comment = {
        type: block ? "Block" : "Line",
        value: text,
        start: start2,
        end
      };
      if (options.locations) {
        comment.loc = new SourceLocation(this, startLoc, endLoc);
      }
      if (options.ranges) {
        comment.range = [start2, end];
      }
      array.push(comment);
    };
  }
  __name(pushComment, "pushComment");
  var SCOPE_TOP = 1;
  var SCOPE_FUNCTION = 2;
  var SCOPE_ASYNC = 4;
  var SCOPE_GENERATOR = 8;
  var SCOPE_ARROW = 16;
  var SCOPE_SIMPLE_CATCH = 32;
  var SCOPE_SUPER = 64;
  var SCOPE_DIRECT_SUPER = 128;
  var SCOPE_CLASS_STATIC_BLOCK = 256;
  var SCOPE_CLASS_FIELD_INIT = 512;
  var SCOPE_VAR = SCOPE_TOP | SCOPE_FUNCTION | SCOPE_CLASS_STATIC_BLOCK;
  function functionFlags(async, generator) {
    return SCOPE_FUNCTION | (async ? SCOPE_ASYNC : 0) | (generator ? SCOPE_GENERATOR : 0);
  }
  __name(functionFlags, "functionFlags");
  var BIND_NONE = 0;
  var BIND_VAR = 1;
  var BIND_LEXICAL = 2;
  var BIND_FUNCTION = 3;
  var BIND_SIMPLE_CATCH = 4;
  var BIND_OUTSIDE = 5;
  var Parser = /* @__PURE__ */ __name(function Parser2(options, input, startPos) {
    this.options = options = getOptions(options);
    this.sourceFile = options.sourceFile;
    this.keywords = wordsRegexp(keywords$1[options.ecmaVersion >= 6 ? 6 : options.sourceType === "module" ? "5module" : 5]);
    var reserved = "";
    if (options.allowReserved !== true) {
      reserved = reservedWords[options.ecmaVersion >= 6 ? 6 : options.ecmaVersion === 5 ? 5 : 3];
      if (options.sourceType === "module") {
        reserved += " await";
      }
    }
    this.reservedWords = wordsRegexp(reserved);
    var reservedStrict = (reserved ? reserved + " " : "") + reservedWords.strict;
    this.reservedWordsStrict = wordsRegexp(reservedStrict);
    this.reservedWordsStrictBind = wordsRegexp(reservedStrict + " " + reservedWords.strictBind);
    this.input = String(input);
    this.containsEsc = false;
    if (startPos) {
      this.pos = startPos;
      this.lineStart = this.input.lastIndexOf("\n", startPos - 1) + 1;
      this.curLine = this.input.slice(0, this.lineStart).split(lineBreak).length;
    } else {
      this.pos = this.lineStart = 0;
      this.curLine = 1;
    }
    this.type = types$1.eof;
    this.value = null;
    this.start = this.end = this.pos;
    this.startLoc = this.endLoc = this.curPosition();
    this.lastTokEndLoc = this.lastTokStartLoc = null;
    this.lastTokStart = this.lastTokEnd = this.pos;
    this.context = this.initialContext();
    this.exprAllowed = true;
    this.inModule = options.sourceType === "module";
    this.strict = this.inModule || this.strictDirective(this.pos);
    this.potentialArrowAt = -1;
    this.potentialArrowInForAwait = false;
    this.yieldPos = this.awaitPos = this.awaitIdentPos = 0;
    this.labels = [];
    this.undefinedExports = /* @__PURE__ */ Object.create(null);
    if (this.pos === 0 && options.allowHashBang && this.input.slice(0, 2) === "#!") {
      this.skipLineComment(2);
    }
    this.scopeStack = [];
    this.enterScope(SCOPE_TOP);
    this.regexpState = null;
    this.privateNameStack = [];
  }, "Parser");
  var prototypeAccessors = { inFunction: { configurable: true }, inGenerator: { configurable: true }, inAsync: { configurable: true }, canAwait: { configurable: true }, allowSuper: { configurable: true }, allowDirectSuper: { configurable: true }, treatFunctionsAsVar: { configurable: true }, allowNewDotTarget: { configurable: true }, inClassStaticBlock: { configurable: true } };
  Parser.prototype.parse = /* @__PURE__ */ __name(function parse() {
    var node = this.options.program || this.startNode();
    this.nextToken();
    return this.parseTopLevel(node);
  }, "parse");
  prototypeAccessors.inFunction.get = function() {
    return (this.currentVarScope().flags & SCOPE_FUNCTION) > 0;
  };
  prototypeAccessors.inGenerator.get = function() {
    return (this.currentVarScope().flags & SCOPE_GENERATOR) > 0;
  };
  prototypeAccessors.inAsync.get = function() {
    return (this.currentVarScope().flags & SCOPE_ASYNC) > 0;
  };
  prototypeAccessors.canAwait.get = function() {
    for (var i = this.scopeStack.length - 1; i >= 0; i--) {
      var ref2 = this.scopeStack[i];
      var flags = ref2.flags;
      if (flags & (SCOPE_CLASS_STATIC_BLOCK | SCOPE_CLASS_FIELD_INIT)) {
        return false;
      }
      if (flags & SCOPE_FUNCTION) {
        return (flags & SCOPE_ASYNC) > 0;
      }
    }
    return this.inModule && this.options.ecmaVersion >= 13 || this.options.allowAwaitOutsideFunction;
  };
  prototypeAccessors.allowSuper.get = function() {
    var ref2 = this.currentThisScope();
    var flags = ref2.flags;
    return (flags & SCOPE_SUPER) > 0 || this.options.allowSuperOutsideMethod;
  };
  prototypeAccessors.allowDirectSuper.get = function() {
    return (this.currentThisScope().flags & SCOPE_DIRECT_SUPER) > 0;
  };
  prototypeAccessors.treatFunctionsAsVar.get = function() {
    return this.treatFunctionsAsVarInScope(this.currentScope());
  };
  prototypeAccessors.allowNewDotTarget.get = function() {
    for (var i = this.scopeStack.length - 1; i >= 0; i--) {
      var ref2 = this.scopeStack[i];
      var flags = ref2.flags;
      if (flags & (SCOPE_CLASS_STATIC_BLOCK | SCOPE_CLASS_FIELD_INIT) || flags & SCOPE_FUNCTION && !(flags & SCOPE_ARROW)) {
        return true;
      }
    }
    return false;
  };
  prototypeAccessors.inClassStaticBlock.get = function() {
    return (this.currentVarScope().flags & SCOPE_CLASS_STATIC_BLOCK) > 0;
  };
  Parser.extend = /* @__PURE__ */ __name(function extend() {
    var plugins = [], len = arguments.length;
    while (len--) plugins[len] = arguments[len];
    var cls = this;
    for (var i = 0; i < plugins.length; i++) {
      cls = plugins[i](cls);
    }
    return cls;
  }, "extend");
  Parser.parse = /* @__PURE__ */ __name(function parse2(input, options) {
    return new this(options, input).parse();
  }, "parse");
  Parser.parseExpressionAt = /* @__PURE__ */ __name(function parseExpressionAt(input, pos, options) {
    var parser = new this(options, input, pos);
    parser.nextToken();
    return parser.parseExpression();
  }, "parseExpressionAt");
  Parser.tokenizer = /* @__PURE__ */ __name(function tokenizer(input, options) {
    return new this(options, input);
  }, "tokenizer");
  Object.defineProperties(Parser.prototype, prototypeAccessors);
  var pp$9 = Parser.prototype;
  var literal = /^(?:'((?:\\[^]|[^'\\])*?)'|"((?:\\[^]|[^"\\])*?)")/;
  pp$9.strictDirective = function(start2) {
    if (this.options.ecmaVersion < 5) {
      return false;
    }
    for (; ; ) {
      skipWhiteSpace.lastIndex = start2;
      start2 += skipWhiteSpace.exec(this.input)[0].length;
      var match = literal.exec(this.input.slice(start2));
      if (!match) {
        return false;
      }
      if ((match[1] || match[2]) === "use strict") {
        skipWhiteSpace.lastIndex = start2 + match[0].length;
        var spaceAfter = skipWhiteSpace.exec(this.input), end = spaceAfter.index + spaceAfter[0].length;
        var next = this.input.charAt(end);
        return next === ";" || next === "}" || lineBreak.test(spaceAfter[0]) && !(/[(`.[+\-/*%<>=,?^&]/.test(next) || next === "!" && this.input.charAt(end + 1) === "=");
      }
      start2 += match[0].length;
      skipWhiteSpace.lastIndex = start2;
      start2 += skipWhiteSpace.exec(this.input)[0].length;
      if (this.input[start2] === ";") {
        start2++;
      }
    }
  };
  pp$9.eat = function(type) {
    if (this.type === type) {
      this.next();
      return true;
    } else {
      return false;
    }
  };
  pp$9.isContextual = function(name) {
    return this.type === types$1.name && this.value === name && !this.containsEsc;
  };
  pp$9.eatContextual = function(name) {
    if (!this.isContextual(name)) {
      return false;
    }
    this.next();
    return true;
  };
  pp$9.expectContextual = function(name) {
    if (!this.eatContextual(name)) {
      this.unexpected();
    }
  };
  pp$9.canInsertSemicolon = function() {
    return this.type === types$1.eof || this.type === types$1.braceR || lineBreak.test(this.input.slice(this.lastTokEnd, this.start));
  };
  pp$9.insertSemicolon = function() {
    if (this.canInsertSemicolon()) {
      if (this.options.onInsertedSemicolon) {
        this.options.onInsertedSemicolon(this.lastTokEnd, this.lastTokEndLoc);
      }
      return true;
    }
  };
  pp$9.semicolon = function() {
    if (!this.eat(types$1.semi) && !this.insertSemicolon()) {
      this.unexpected();
    }
  };
  pp$9.afterTrailingComma = function(tokType, notNext) {
    if (this.type === tokType) {
      if (this.options.onTrailingComma) {
        this.options.onTrailingComma(this.lastTokStart, this.lastTokStartLoc);
      }
      if (!notNext) {
        this.next();
      }
      return true;
    }
  };
  pp$9.expect = function(type) {
    this.eat(type) || this.unexpected();
  };
  pp$9.unexpected = function(pos) {
    this.raise(pos != null ? pos : this.start, "Unexpected token");
  };
  var DestructuringErrors = /* @__PURE__ */ __name(function DestructuringErrors2() {
    this.shorthandAssign = this.trailingComma = this.parenthesizedAssign = this.parenthesizedBind = this.doubleProto = -1;
  }, "DestructuringErrors");
  pp$9.checkPatternErrors = function(refDestructuringErrors, isAssign) {
    if (!refDestructuringErrors) {
      return;
    }
    if (refDestructuringErrors.trailingComma > -1) {
      this.raiseRecoverable(refDestructuringErrors.trailingComma, "Comma is not permitted after the rest element");
    }
    var parens = isAssign ? refDestructuringErrors.parenthesizedAssign : refDestructuringErrors.parenthesizedBind;
    if (parens > -1) {
      this.raiseRecoverable(parens, isAssign ? "Assigning to rvalue" : "Parenthesized pattern");
    }
  };
  pp$9.checkExpressionErrors = function(refDestructuringErrors, andThrow) {
    if (!refDestructuringErrors) {
      return false;
    }
    var shorthandAssign = refDestructuringErrors.shorthandAssign;
    var doubleProto = refDestructuringErrors.doubleProto;
    if (!andThrow) {
      return shorthandAssign >= 0 || doubleProto >= 0;
    }
    if (shorthandAssign >= 0) {
      this.raise(shorthandAssign, "Shorthand property assignments are valid only in destructuring patterns");
    }
    if (doubleProto >= 0) {
      this.raiseRecoverable(doubleProto, "Redefinition of __proto__ property");
    }
  };
  pp$9.checkYieldAwaitInDefaultParams = function() {
    if (this.yieldPos && (!this.awaitPos || this.yieldPos < this.awaitPos)) {
      this.raise(this.yieldPos, "Yield expression cannot be a default value");
    }
    if (this.awaitPos) {
      this.raise(this.awaitPos, "Await expression cannot be a default value");
    }
  };
  pp$9.isSimpleAssignTarget = function(expr) {
    if (expr.type === "ParenthesizedExpression") {
      return this.isSimpleAssignTarget(expr.expression);
    }
    return expr.type === "Identifier" || expr.type === "MemberExpression";
  };
  var pp$8 = Parser.prototype;
  pp$8.parseTopLevel = function(node) {
    var exports = /* @__PURE__ */ Object.create(null);
    if (!node.body) {
      node.body = [];
    }
    while (this.type !== types$1.eof) {
      var stmt = this.parseStatement(null, true, exports);
      node.body.push(stmt);
    }
    if (this.inModule) {
      for (var i = 0, list = Object.keys(this.undefinedExports); i < list.length; i += 1) {
        var name = list[i];
        this.raiseRecoverable(this.undefinedExports[name].start, "Export '" + name + "' is not defined");
      }
    }
    this.adaptDirectivePrologue(node.body);
    this.next();
    node.sourceType = this.options.sourceType;
    return this.finishNode(node, "Program");
  };
  var loopLabel = { kind: "loop" };
  var switchLabel = { kind: "switch" };
  pp$8.isLet = function(context) {
    if (this.options.ecmaVersion < 6 || !this.isContextual("let")) {
      return false;
    }
    skipWhiteSpace.lastIndex = this.pos;
    var skip = skipWhiteSpace.exec(this.input);
    var next = this.pos + skip[0].length, nextCh = this.input.charCodeAt(next);
    if (nextCh === 91 || nextCh === 92) {
      return true;
    }
    if (context) {
      return false;
    }
    if (nextCh === 123 || nextCh > 55295 && nextCh < 56320) {
      return true;
    }
    if (isIdentifierStart(nextCh, true)) {
      var pos = next + 1;
      while (isIdentifierChar(nextCh = this.input.charCodeAt(pos), true)) {
        ++pos;
      }
      if (nextCh === 92 || nextCh > 55295 && nextCh < 56320) {
        return true;
      }
      var ident = this.input.slice(next, pos);
      if (!keywordRelationalOperator.test(ident)) {
        return true;
      }
    }
    return false;
  };
  pp$8.isAsyncFunction = function() {
    if (this.options.ecmaVersion < 8 || !this.isContextual("async")) {
      return false;
    }
    skipWhiteSpace.lastIndex = this.pos;
    var skip = skipWhiteSpace.exec(this.input);
    var next = this.pos + skip[0].length, after;
    return !lineBreak.test(this.input.slice(this.pos, next)) && this.input.slice(next, next + 8) === "function" && (next + 8 === this.input.length || !(isIdentifierChar(after = this.input.charCodeAt(next + 8)) || after > 55295 && after < 56320));
  };
  pp$8.isUsingKeyword = function(isAwaitUsing, isFor) {
    if (this.options.ecmaVersion < 17 || !this.isContextual(isAwaitUsing ? "await" : "using")) {
      return false;
    }
    skipWhiteSpace.lastIndex = this.pos;
    var skip = skipWhiteSpace.exec(this.input);
    var next = this.pos + skip[0].length;
    if (lineBreak.test(this.input.slice(this.pos, next))) {
      return false;
    }
    if (isAwaitUsing) {
      var awaitEndPos = next + 5, after;
      if (this.input.slice(next, awaitEndPos) !== "using" || awaitEndPos === this.input.length || isIdentifierChar(after = this.input.charCodeAt(awaitEndPos)) || after > 55295 && after < 56320) {
        return false;
      }
      skipWhiteSpace.lastIndex = awaitEndPos;
      var skipAfterUsing = skipWhiteSpace.exec(this.input);
      if (skipAfterUsing && lineBreak.test(this.input.slice(awaitEndPos, awaitEndPos + skipAfterUsing[0].length))) {
        return false;
      }
    }
    if (isFor) {
      var ofEndPos = next + 2, after$1;
      if (this.input.slice(next, ofEndPos) === "of") {
        if (ofEndPos === this.input.length || !isIdentifierChar(after$1 = this.input.charCodeAt(ofEndPos)) && !(after$1 > 55295 && after$1 < 56320)) {
          return false;
        }
      }
    }
    var ch = this.input.charCodeAt(next);
    return isIdentifierStart(ch, true) || ch === 92;
  };
  pp$8.isAwaitUsing = function(isFor) {
    return this.isUsingKeyword(true, isFor);
  };
  pp$8.isUsing = function(isFor) {
    return this.isUsingKeyword(false, isFor);
  };
  pp$8.parseStatement = function(context, topLevel, exports) {
    var starttype = this.type, node = this.startNode(), kind;
    if (this.isLet(context)) {
      starttype = types$1._var;
      kind = "let";
    }
    switch (starttype) {
      case types$1._break:
      case types$1._continue:
        return this.parseBreakContinueStatement(node, starttype.keyword);
      case types$1._debugger:
        return this.parseDebuggerStatement(node);
      case types$1._do:
        return this.parseDoStatement(node);
      case types$1._for:
        return this.parseForStatement(node);
      case types$1._function:
        if (context && (this.strict || context !== "if" && context !== "label") && this.options.ecmaVersion >= 6) {
          this.unexpected();
        }
        return this.parseFunctionStatement(node, false, !context);
      case types$1._class:
        if (context) {
          this.unexpected();
        }
        return this.parseClass(node, true);
      case types$1._if:
        return this.parseIfStatement(node);
      case types$1._return:
        return this.parseReturnStatement(node);
      case types$1._switch:
        return this.parseSwitchStatement(node);
      case types$1._throw:
        return this.parseThrowStatement(node);
      case types$1._try:
        return this.parseTryStatement(node);
      case types$1._const:
      case types$1._var:
        kind = kind || this.value;
        if (context && kind !== "var") {
          this.unexpected();
        }
        return this.parseVarStatement(node, kind);
      case types$1._while:
        return this.parseWhileStatement(node);
      case types$1._with:
        return this.parseWithStatement(node);
      case types$1.braceL:
        return this.parseBlock(true, node);
      case types$1.semi:
        return this.parseEmptyStatement(node);
      case types$1._export:
      case types$1._import:
        if (this.options.ecmaVersion > 10 && starttype === types$1._import) {
          skipWhiteSpace.lastIndex = this.pos;
          var skip = skipWhiteSpace.exec(this.input);
          var next = this.pos + skip[0].length, nextCh = this.input.charCodeAt(next);
          if (nextCh === 40 || nextCh === 46) {
            return this.parseExpressionStatement(node, this.parseExpression());
          }
        }
        if (!this.options.allowImportExportEverywhere) {
          if (!topLevel) {
            this.raise(this.start, "'import' and 'export' may only appear at the top level");
          }
          if (!this.inModule) {
            this.raise(this.start, "'import' and 'export' may appear only with 'sourceType: module'");
          }
        }
        return starttype === types$1._import ? this.parseImport(node) : this.parseExport(node, exports);
      // If the statement does not start with a statement keyword or a
      // brace, it's an ExpressionStatement or LabeledStatement. We
      // simply start parsing an expression, and afterwards, if the
      // next token is a colon and the expression was a simple
      // Identifier node, we switch to interpreting it as a label.
      default:
        if (this.isAsyncFunction()) {
          if (context) {
            this.unexpected();
          }
          this.next();
          return this.parseFunctionStatement(node, true, !context);
        }
        var usingKind = this.isAwaitUsing(false) ? "await using" : this.isUsing(false) ? "using" : null;
        if (usingKind) {
          if (topLevel && this.options.sourceType === "script") {
            this.raise(this.start, "Using declaration cannot appear in the top level when source type is `script`");
          }
          if (usingKind === "await using") {
            if (!this.canAwait) {
              this.raise(this.start, "Await using cannot appear outside of async function");
            }
            this.next();
          }
          this.next();
          this.parseVar(node, false, usingKind);
          this.semicolon();
          return this.finishNode(node, "VariableDeclaration");
        }
        var maybeName = this.value, expr = this.parseExpression();
        if (starttype === types$1.name && expr.type === "Identifier" && this.eat(types$1.colon)) {
          return this.parseLabeledStatement(node, maybeName, expr, context);
        } else {
          return this.parseExpressionStatement(node, expr);
        }
    }
  };
  pp$8.parseBreakContinueStatement = function(node, keyword) {
    var isBreak = keyword === "break";
    this.next();
    if (this.eat(types$1.semi) || this.insertSemicolon()) {
      node.label = null;
    } else if (this.type !== types$1.name) {
      this.unexpected();
    } else {
      node.label = this.parseIdent();
      this.semicolon();
    }
    var i = 0;
    for (; i < this.labels.length; ++i) {
      var lab = this.labels[i];
      if (node.label == null || lab.name === node.label.name) {
        if (lab.kind != null && (isBreak || lab.kind === "loop")) {
          break;
        }
        if (node.label && isBreak) {
          break;
        }
      }
    }
    if (i === this.labels.length) {
      this.raise(node.start, "Unsyntactic " + keyword);
    }
    return this.finishNode(node, isBreak ? "BreakStatement" : "ContinueStatement");
  };
  pp$8.parseDebuggerStatement = function(node) {
    this.next();
    this.semicolon();
    return this.finishNode(node, "DebuggerStatement");
  };
  pp$8.parseDoStatement = function(node) {
    this.next();
    this.labels.push(loopLabel);
    node.body = this.parseStatement("do");
    this.labels.pop();
    this.expect(types$1._while);
    node.test = this.parseParenExpression();
    if (this.options.ecmaVersion >= 6) {
      this.eat(types$1.semi);
    } else {
      this.semicolon();
    }
    return this.finishNode(node, "DoWhileStatement");
  };
  pp$8.parseForStatement = function(node) {
    this.next();
    var awaitAt = this.options.ecmaVersion >= 9 && this.canAwait && this.eatContextual("await") ? this.lastTokStart : -1;
    this.labels.push(loopLabel);
    this.enterScope(0);
    this.expect(types$1.parenL);
    if (this.type === types$1.semi) {
      if (awaitAt > -1) {
        this.unexpected(awaitAt);
      }
      return this.parseFor(node, null);
    }
    var isLet = this.isLet();
    if (this.type === types$1._var || this.type === types$1._const || isLet) {
      var init$1 = this.startNode(), kind = isLet ? "let" : this.value;
      this.next();
      this.parseVar(init$1, true, kind);
      this.finishNode(init$1, "VariableDeclaration");
      return this.parseForAfterInit(node, init$1, awaitAt);
    }
    var startsWithLet = this.isContextual("let"), isForOf = false;
    var usingKind = this.isUsing(true) ? "using" : this.isAwaitUsing(true) ? "await using" : null;
    if (usingKind) {
      var init$2 = this.startNode();
      this.next();
      if (usingKind === "await using") {
        this.next();
      }
      this.parseVar(init$2, true, usingKind);
      this.finishNode(init$2, "VariableDeclaration");
      return this.parseForAfterInit(node, init$2, awaitAt);
    }
    var containsEsc = this.containsEsc;
    var refDestructuringErrors = new DestructuringErrors();
    var initPos = this.start;
    var init = awaitAt > -1 ? this.parseExprSubscripts(refDestructuringErrors, "await") : this.parseExpression(true, refDestructuringErrors);
    if (this.type === types$1._in || (isForOf = this.options.ecmaVersion >= 6 && this.isContextual("of"))) {
      if (awaitAt > -1) {
        if (this.type === types$1._in) {
          this.unexpected(awaitAt);
        }
        node.await = true;
      } else if (isForOf && this.options.ecmaVersion >= 8) {
        if (init.start === initPos && !containsEsc && init.type === "Identifier" && init.name === "async") {
          this.unexpected();
        } else if (this.options.ecmaVersion >= 9) {
          node.await = false;
        }
      }
      if (startsWithLet && isForOf) {
        this.raise(init.start, "The left-hand side of a for-of loop may not start with 'let'.");
      }
      this.toAssignable(init, false, refDestructuringErrors);
      this.checkLValPattern(init);
      return this.parseForIn(node, init);
    } else {
      this.checkExpressionErrors(refDestructuringErrors, true);
    }
    if (awaitAt > -1) {
      this.unexpected(awaitAt);
    }
    return this.parseFor(node, init);
  };
  pp$8.parseForAfterInit = function(node, init, awaitAt) {
    if ((this.type === types$1._in || this.options.ecmaVersion >= 6 && this.isContextual("of")) && init.declarations.length === 1) {
      if (this.options.ecmaVersion >= 9) {
        if (this.type === types$1._in) {
          if (awaitAt > -1) {
            this.unexpected(awaitAt);
          }
        } else {
          node.await = awaitAt > -1;
        }
      }
      return this.parseForIn(node, init);
    }
    if (awaitAt > -1) {
      this.unexpected(awaitAt);
    }
    return this.parseFor(node, init);
  };
  pp$8.parseFunctionStatement = function(node, isAsync, declarationPosition) {
    this.next();
    return this.parseFunction(node, FUNC_STATEMENT | (declarationPosition ? 0 : FUNC_HANGING_STATEMENT), false, isAsync);
  };
  pp$8.parseIfStatement = function(node) {
    this.next();
    node.test = this.parseParenExpression();
    node.consequent = this.parseStatement("if");
    node.alternate = this.eat(types$1._else) ? this.parseStatement("if") : null;
    return this.finishNode(node, "IfStatement");
  };
  pp$8.parseReturnStatement = function(node) {
    if (!this.inFunction && !this.options.allowReturnOutsideFunction) {
      this.raise(this.start, "'return' outside of function");
    }
    this.next();
    if (this.eat(types$1.semi) || this.insertSemicolon()) {
      node.argument = null;
    } else {
      node.argument = this.parseExpression();
      this.semicolon();
    }
    return this.finishNode(node, "ReturnStatement");
  };
  pp$8.parseSwitchStatement = function(node) {
    this.next();
    node.discriminant = this.parseParenExpression();
    node.cases = [];
    this.expect(types$1.braceL);
    this.labels.push(switchLabel);
    this.enterScope(0);
    var cur;
    for (var sawDefault = false; this.type !== types$1.braceR; ) {
      if (this.type === types$1._case || this.type === types$1._default) {
        var isCase = this.type === types$1._case;
        if (cur) {
          this.finishNode(cur, "SwitchCase");
        }
        node.cases.push(cur = this.startNode());
        cur.consequent = [];
        this.next();
        if (isCase) {
          cur.test = this.parseExpression();
        } else {
          if (sawDefault) {
            this.raiseRecoverable(this.lastTokStart, "Multiple default clauses");
          }
          sawDefault = true;
          cur.test = null;
        }
        this.expect(types$1.colon);
      } else {
        if (!cur) {
          this.unexpected();
        }
        cur.consequent.push(this.parseStatement(null));
      }
    }
    this.exitScope();
    if (cur) {
      this.finishNode(cur, "SwitchCase");
    }
    this.next();
    this.labels.pop();
    return this.finishNode(node, "SwitchStatement");
  };
  pp$8.parseThrowStatement = function(node) {
    this.next();
    if (lineBreak.test(this.input.slice(this.lastTokEnd, this.start))) {
      this.raise(this.lastTokEnd, "Illegal newline after throw");
    }
    node.argument = this.parseExpression();
    this.semicolon();
    return this.finishNode(node, "ThrowStatement");
  };
  var empty$1 = [];
  pp$8.parseCatchClauseParam = function() {
    var param = this.parseBindingAtom();
    var simple = param.type === "Identifier";
    this.enterScope(simple ? SCOPE_SIMPLE_CATCH : 0);
    this.checkLValPattern(param, simple ? BIND_SIMPLE_CATCH : BIND_LEXICAL);
    this.expect(types$1.parenR);
    return param;
  };
  pp$8.parseTryStatement = function(node) {
    this.next();
    node.block = this.parseBlock();
    node.handler = null;
    if (this.type === types$1._catch) {
      var clause = this.startNode();
      this.next();
      if (this.eat(types$1.parenL)) {
        clause.param = this.parseCatchClauseParam();
      } else {
        if (this.options.ecmaVersion < 10) {
          this.unexpected();
        }
        clause.param = null;
        this.enterScope(0);
      }
      clause.body = this.parseBlock(false);
      this.exitScope();
      node.handler = this.finishNode(clause, "CatchClause");
    }
    node.finalizer = this.eat(types$1._finally) ? this.parseBlock() : null;
    if (!node.handler && !node.finalizer) {
      this.raise(node.start, "Missing catch or finally clause");
    }
    return this.finishNode(node, "TryStatement");
  };
  pp$8.parseVarStatement = function(node, kind, allowMissingInitializer) {
    this.next();
    this.parseVar(node, false, kind, allowMissingInitializer);
    this.semicolon();
    return this.finishNode(node, "VariableDeclaration");
  };
  pp$8.parseWhileStatement = function(node) {
    this.next();
    node.test = this.parseParenExpression();
    this.labels.push(loopLabel);
    node.body = this.parseStatement("while");
    this.labels.pop();
    return this.finishNode(node, "WhileStatement");
  };
  pp$8.parseWithStatement = function(node) {
    if (this.strict) {
      this.raise(this.start, "'with' in strict mode");
    }
    this.next();
    node.object = this.parseParenExpression();
    node.body = this.parseStatement("with");
    return this.finishNode(node, "WithStatement");
  };
  pp$8.parseEmptyStatement = function(node) {
    this.next();
    return this.finishNode(node, "EmptyStatement");
  };
  pp$8.parseLabeledStatement = function(node, maybeName, expr, context) {
    for (var i$1 = 0, list = this.labels; i$1 < list.length; i$1 += 1) {
      var label = list[i$1];
      if (label.name === maybeName) {
        this.raise(expr.start, "Label '" + maybeName + "' is already declared");
      }
    }
    var kind = this.type.isLoop ? "loop" : this.type === types$1._switch ? "switch" : null;
    for (var i = this.labels.length - 1; i >= 0; i--) {
      var label$1 = this.labels[i];
      if (label$1.statementStart === node.start) {
        label$1.statementStart = this.start;
        label$1.kind = kind;
      } else {
        break;
      }
    }
    this.labels.push({ name: maybeName, kind, statementStart: this.start });
    node.body = this.parseStatement(context ? context.indexOf("label") === -1 ? context + "label" : context : "label");
    this.labels.pop();
    node.label = expr;
    return this.finishNode(node, "LabeledStatement");
  };
  pp$8.parseExpressionStatement = function(node, expr) {
    node.expression = expr;
    this.semicolon();
    return this.finishNode(node, "ExpressionStatement");
  };
  pp$8.parseBlock = function(createNewLexicalScope, node, exitStrict) {
    if (createNewLexicalScope === void 0) createNewLexicalScope = true;
    if (node === void 0) node = this.startNode();
    node.body = [];
    this.expect(types$1.braceL);
    if (createNewLexicalScope) {
      this.enterScope(0);
    }
    while (this.type !== types$1.braceR) {
      var stmt = this.parseStatement(null);
      node.body.push(stmt);
    }
    if (exitStrict) {
      this.strict = false;
    }
    this.next();
    if (createNewLexicalScope) {
      this.exitScope();
    }
    return this.finishNode(node, "BlockStatement");
  };
  pp$8.parseFor = function(node, init) {
    node.init = init;
    this.expect(types$1.semi);
    node.test = this.type === types$1.semi ? null : this.parseExpression();
    this.expect(types$1.semi);
    node.update = this.type === types$1.parenR ? null : this.parseExpression();
    this.expect(types$1.parenR);
    node.body = this.parseStatement("for");
    this.exitScope();
    this.labels.pop();
    return this.finishNode(node, "ForStatement");
  };
  pp$8.parseForIn = function(node, init) {
    var isForIn = this.type === types$1._in;
    this.next();
    if (init.type === "VariableDeclaration" && init.declarations[0].init != null && (!isForIn || this.options.ecmaVersion < 8 || this.strict || init.kind !== "var" || init.declarations[0].id.type !== "Identifier")) {
      this.raise(
        init.start,
        (isForIn ? "for-in" : "for-of") + " loop variable declaration may not have an initializer"
      );
    }
    node.left = init;
    node.right = isForIn ? this.parseExpression() : this.parseMaybeAssign();
    this.expect(types$1.parenR);
    node.body = this.parseStatement("for");
    this.exitScope();
    this.labels.pop();
    return this.finishNode(node, isForIn ? "ForInStatement" : "ForOfStatement");
  };
  pp$8.parseVar = function(node, isFor, kind, allowMissingInitializer) {
    node.declarations = [];
    node.kind = kind;
    for (; ; ) {
      var decl = this.startNode();
      this.parseVarId(decl, kind);
      if (this.eat(types$1.eq)) {
        decl.init = this.parseMaybeAssign(isFor);
      } else if (!allowMissingInitializer && kind === "const" && !(this.type === types$1._in || this.options.ecmaVersion >= 6 && this.isContextual("of"))) {
        this.unexpected();
      } else if (!allowMissingInitializer && (kind === "using" || kind === "await using") && this.options.ecmaVersion >= 17 && this.type !== types$1._in && !this.isContextual("of")) {
        this.raise(this.lastTokEnd, "Missing initializer in " + kind + " declaration");
      } else if (!allowMissingInitializer && decl.id.type !== "Identifier" && !(isFor && (this.type === types$1._in || this.isContextual("of")))) {
        this.raise(this.lastTokEnd, "Complex binding patterns require an initialization value");
      } else {
        decl.init = null;
      }
      node.declarations.push(this.finishNode(decl, "VariableDeclarator"));
      if (!this.eat(types$1.comma)) {
        break;
      }
    }
    return node;
  };
  pp$8.parseVarId = function(decl, kind) {
    decl.id = kind === "using" || kind === "await using" ? this.parseIdent() : this.parseBindingAtom();
    this.checkLValPattern(decl.id, kind === "var" ? BIND_VAR : BIND_LEXICAL, false);
  };
  var FUNC_STATEMENT = 1;
  var FUNC_HANGING_STATEMENT = 2;
  var FUNC_NULLABLE_ID = 4;
  pp$8.parseFunction = function(node, statement, allowExpressionBody, isAsync, forInit) {
    this.initFunction(node);
    if (this.options.ecmaVersion >= 9 || this.options.ecmaVersion >= 6 && !isAsync) {
      if (this.type === types$1.star && statement & FUNC_HANGING_STATEMENT) {
        this.unexpected();
      }
      node.generator = this.eat(types$1.star);
    }
    if (this.options.ecmaVersion >= 8) {
      node.async = !!isAsync;
    }
    if (statement & FUNC_STATEMENT) {
      node.id = statement & FUNC_NULLABLE_ID && this.type !== types$1.name ? null : this.parseIdent();
      if (node.id && !(statement & FUNC_HANGING_STATEMENT)) {
        this.checkLValSimple(node.id, this.strict || node.generator || node.async ? this.treatFunctionsAsVar ? BIND_VAR : BIND_LEXICAL : BIND_FUNCTION);
      }
    }
    var oldYieldPos = this.yieldPos, oldAwaitPos = this.awaitPos, oldAwaitIdentPos = this.awaitIdentPos;
    this.yieldPos = 0;
    this.awaitPos = 0;
    this.awaitIdentPos = 0;
    this.enterScope(functionFlags(node.async, node.generator));
    if (!(statement & FUNC_STATEMENT)) {
      node.id = this.type === types$1.name ? this.parseIdent() : null;
    }
    this.parseFunctionParams(node);
    this.parseFunctionBody(node, allowExpressionBody, false, forInit);
    this.yieldPos = oldYieldPos;
    this.awaitPos = oldAwaitPos;
    this.awaitIdentPos = oldAwaitIdentPos;
    return this.finishNode(node, statement & FUNC_STATEMENT ? "FunctionDeclaration" : "FunctionExpression");
  };
  pp$8.parseFunctionParams = function(node) {
    this.expect(types$1.parenL);
    node.params = this.parseBindingList(types$1.parenR, false, this.options.ecmaVersion >= 8);
    this.checkYieldAwaitInDefaultParams();
  };
  pp$8.parseClass = function(node, isStatement) {
    this.next();
    var oldStrict = this.strict;
    this.strict = true;
    this.parseClassId(node, isStatement);
    this.parseClassSuper(node);
    var privateNameMap = this.enterClassBody();
    var classBody = this.startNode();
    var hadConstructor = false;
    classBody.body = [];
    this.expect(types$1.braceL);
    while (this.type !== types$1.braceR) {
      var element = this.parseClassElement(node.superClass !== null);
      if (element) {
        classBody.body.push(element);
        if (element.type === "MethodDefinition" && element.kind === "constructor") {
          if (hadConstructor) {
            this.raiseRecoverable(element.start, "Duplicate constructor in the same class");
          }
          hadConstructor = true;
        } else if (element.key && element.key.type === "PrivateIdentifier" && isPrivateNameConflicted(privateNameMap, element)) {
          this.raiseRecoverable(element.key.start, "Identifier '#" + element.key.name + "' has already been declared");
        }
      }
    }
    this.strict = oldStrict;
    this.next();
    node.body = this.finishNode(classBody, "ClassBody");
    this.exitClassBody();
    return this.finishNode(node, isStatement ? "ClassDeclaration" : "ClassExpression");
  };
  pp$8.parseClassElement = function(constructorAllowsSuper) {
    if (this.eat(types$1.semi)) {
      return null;
    }
    var ecmaVersion = this.options.ecmaVersion;
    var node = this.startNode();
    var keyName = "";
    var isGenerator = false;
    var isAsync = false;
    var kind = "method";
    var isStatic = false;
    if (this.eatContextual("static")) {
      if (ecmaVersion >= 13 && this.eat(types$1.braceL)) {
        this.parseClassStaticBlock(node);
        return node;
      }
      if (this.isClassElementNameStart() || this.type === types$1.star) {
        isStatic = true;
      } else {
        keyName = "static";
      }
    }
    node.static = isStatic;
    if (!keyName && ecmaVersion >= 8 && this.eatContextual("async")) {
      if ((this.isClassElementNameStart() || this.type === types$1.star) && !this.canInsertSemicolon()) {
        isAsync = true;
      } else {
        keyName = "async";
      }
    }
    if (!keyName && (ecmaVersion >= 9 || !isAsync) && this.eat(types$1.star)) {
      isGenerator = true;
    }
    if (!keyName && !isAsync && !isGenerator) {
      var lastValue = this.value;
      if (this.eatContextual("get") || this.eatContextual("set")) {
        if (this.isClassElementNameStart()) {
          kind = lastValue;
        } else {
          keyName = lastValue;
        }
      }
    }
    if (keyName) {
      node.computed = false;
      node.key = this.startNodeAt(this.lastTokStart, this.lastTokStartLoc);
      node.key.name = keyName;
      this.finishNode(node.key, "Identifier");
    } else {
      this.parseClassElementName(node);
    }
    if (ecmaVersion < 13 || this.type === types$1.parenL || kind !== "method" || isGenerator || isAsync) {
      var isConstructor = !node.static && checkKeyName(node, "constructor");
      var allowsDirectSuper = isConstructor && constructorAllowsSuper;
      if (isConstructor && kind !== "method") {
        this.raise(node.key.start, "Constructor can't have get/set modifier");
      }
      node.kind = isConstructor ? "constructor" : kind;
      this.parseClassMethod(node, isGenerator, isAsync, allowsDirectSuper);
    } else {
      this.parseClassField(node);
    }
    return node;
  };
  pp$8.isClassElementNameStart = function() {
    return this.type === types$1.name || this.type === types$1.privateId || this.type === types$1.num || this.type === types$1.string || this.type === types$1.bracketL || this.type.keyword;
  };
  pp$8.parseClassElementName = function(element) {
    if (this.type === types$1.privateId) {
      if (this.value === "constructor") {
        this.raise(this.start, "Classes can't have an element named '#constructor'");
      }
      element.computed = false;
      element.key = this.parsePrivateIdent();
    } else {
      this.parsePropertyName(element);
    }
  };
  pp$8.parseClassMethod = function(method, isGenerator, isAsync, allowsDirectSuper) {
    var key = method.key;
    if (method.kind === "constructor") {
      if (isGenerator) {
        this.raise(key.start, "Constructor can't be a generator");
      }
      if (isAsync) {
        this.raise(key.start, "Constructor can't be an async method");
      }
    } else if (method.static && checkKeyName(method, "prototype")) {
      this.raise(key.start, "Classes may not have a static property named prototype");
    }
    var value = method.value = this.parseMethod(isGenerator, isAsync, allowsDirectSuper);
    if (method.kind === "get" && value.params.length !== 0) {
      this.raiseRecoverable(value.start, "getter should have no params");
    }
    if (method.kind === "set" && value.params.length !== 1) {
      this.raiseRecoverable(value.start, "setter should have exactly one param");
    }
    if (method.kind === "set" && value.params[0].type === "RestElement") {
      this.raiseRecoverable(value.params[0].start, "Setter cannot use rest params");
    }
    return this.finishNode(method, "MethodDefinition");
  };
  pp$8.parseClassField = function(field) {
    if (checkKeyName(field, "constructor")) {
      this.raise(field.key.start, "Classes can't have a field named 'constructor'");
    } else if (field.static && checkKeyName(field, "prototype")) {
      this.raise(field.key.start, "Classes can't have a static field named 'prototype'");
    }
    if (this.eat(types$1.eq)) {
      this.enterScope(SCOPE_CLASS_FIELD_INIT | SCOPE_SUPER);
      field.value = this.parseMaybeAssign();
      this.exitScope();
    } else {
      field.value = null;
    }
    this.semicolon();
    return this.finishNode(field, "PropertyDefinition");
  };
  pp$8.parseClassStaticBlock = function(node) {
    node.body = [];
    var oldLabels = this.labels;
    this.labels = [];
    this.enterScope(SCOPE_CLASS_STATIC_BLOCK | SCOPE_SUPER);
    while (this.type !== types$1.braceR) {
      var stmt = this.parseStatement(null);
      node.body.push(stmt);
    }
    this.next();
    this.exitScope();
    this.labels = oldLabels;
    return this.finishNode(node, "StaticBlock");
  };
  pp$8.parseClassId = function(node, isStatement) {
    if (this.type === types$1.name) {
      node.id = this.parseIdent();
      if (isStatement) {
        this.checkLValSimple(node.id, BIND_LEXICAL, false);
      }
    } else {
      if (isStatement === true) {
        this.unexpected();
      }
      node.id = null;
    }
  };
  pp$8.parseClassSuper = function(node) {
    node.superClass = this.eat(types$1._extends) ? this.parseExprSubscripts(null, false) : null;
  };
  pp$8.enterClassBody = function() {
    var element = { declared: /* @__PURE__ */ Object.create(null), used: [] };
    this.privateNameStack.push(element);
    return element.declared;
  };
  pp$8.exitClassBody = function() {
    var ref2 = this.privateNameStack.pop();
    var declared = ref2.declared;
    var used = ref2.used;
    if (!this.options.checkPrivateFields) {
      return;
    }
    var len = this.privateNameStack.length;
    var parent = len === 0 ? null : this.privateNameStack[len - 1];
    for (var i = 0; i < used.length; ++i) {
      var id = used[i];
      if (!hasOwn(declared, id.name)) {
        if (parent) {
          parent.used.push(id);
        } else {
          this.raiseRecoverable(id.start, "Private field '#" + id.name + "' must be declared in an enclosing class");
        }
      }
    }
  };
  function isPrivateNameConflicted(privateNameMap, element) {
    var name = element.key.name;
    var curr = privateNameMap[name];
    var next = "true";
    if (element.type === "MethodDefinition" && (element.kind === "get" || element.kind === "set")) {
      next = (element.static ? "s" : "i") + element.kind;
    }
    if (curr === "iget" && next === "iset" || curr === "iset" && next === "iget" || curr === "sget" && next === "sset" || curr === "sset" && next === "sget") {
      privateNameMap[name] = "true";
      return false;
    } else if (!curr) {
      privateNameMap[name] = next;
      return false;
    } else {
      return true;
    }
  }
  __name(isPrivateNameConflicted, "isPrivateNameConflicted");
  function checkKeyName(node, name) {
    var computed = node.computed;
    var key = node.key;
    return !computed && (key.type === "Identifier" && key.name === name || key.type === "Literal" && key.value === name);
  }
  __name(checkKeyName, "checkKeyName");
  pp$8.parseExportAllDeclaration = function(node, exports) {
    if (this.options.ecmaVersion >= 11) {
      if (this.eatContextual("as")) {
        node.exported = this.parseModuleExportName();
        this.checkExport(exports, node.exported, this.lastTokStart);
      } else {
        node.exported = null;
      }
    }
    this.expectContextual("from");
    if (this.type !== types$1.string) {
      this.unexpected();
    }
    node.source = this.parseExprAtom();
    if (this.options.ecmaVersion >= 16) {
      node.attributes = this.parseWithClause();
    }
    this.semicolon();
    return this.finishNode(node, "ExportAllDeclaration");
  };
  pp$8.parseExport = function(node, exports) {
    this.next();
    if (this.eat(types$1.star)) {
      return this.parseExportAllDeclaration(node, exports);
    }
    if (this.eat(types$1._default)) {
      this.checkExport(exports, "default", this.lastTokStart);
      node.declaration = this.parseExportDefaultDeclaration();
      return this.finishNode(node, "ExportDefaultDeclaration");
    }
    if (this.shouldParseExportStatement()) {
      node.declaration = this.parseExportDeclaration(node);
      if (node.declaration.type === "VariableDeclaration") {
        this.checkVariableExport(exports, node.declaration.declarations);
      } else {
        this.checkExport(exports, node.declaration.id, node.declaration.id.start);
      }
      node.specifiers = [];
      node.source = null;
      if (this.options.ecmaVersion >= 16) {
        node.attributes = [];
      }
    } else {
      node.declaration = null;
      node.specifiers = this.parseExportSpecifiers(exports);
      if (this.eatContextual("from")) {
        if (this.type !== types$1.string) {
          this.unexpected();
        }
        node.source = this.parseExprAtom();
        if (this.options.ecmaVersion >= 16) {
          node.attributes = this.parseWithClause();
        }
      } else {
        for (var i = 0, list = node.specifiers; i < list.length; i += 1) {
          var spec = list[i];
          this.checkUnreserved(spec.local);
          this.checkLocalExport(spec.local);
          if (spec.local.type === "Literal") {
            this.raise(spec.local.start, "A string literal cannot be used as an exported binding without `from`.");
          }
        }
        node.source = null;
        if (this.options.ecmaVersion >= 16) {
          node.attributes = [];
        }
      }
      this.semicolon();
    }
    return this.finishNode(node, "ExportNamedDeclaration");
  };
  pp$8.parseExportDeclaration = function(node) {
    return this.parseStatement(null);
  };
  pp$8.parseExportDefaultDeclaration = function() {
    var isAsync;
    if (this.type === types$1._function || (isAsync = this.isAsyncFunction())) {
      var fNode = this.startNode();
      this.next();
      if (isAsync) {
        this.next();
      }
      return this.parseFunction(fNode, FUNC_STATEMENT | FUNC_NULLABLE_ID, false, isAsync);
    } else if (this.type === types$1._class) {
      var cNode = this.startNode();
      return this.parseClass(cNode, "nullableID");
    } else {
      var declaration = this.parseMaybeAssign();
      this.semicolon();
      return declaration;
    }
  };
  pp$8.checkExport = function(exports, name, pos) {
    if (!exports) {
      return;
    }
    if (typeof name !== "string") {
      name = name.type === "Identifier" ? name.name : name.value;
    }
    if (hasOwn(exports, name)) {
      this.raiseRecoverable(pos, "Duplicate export '" + name + "'");
    }
    exports[name] = true;
  };
  pp$8.checkPatternExport = function(exports, pat) {
    var type = pat.type;
    if (type === "Identifier") {
      this.checkExport(exports, pat, pat.start);
    } else if (type === "ObjectPattern") {
      for (var i = 0, list = pat.properties; i < list.length; i += 1) {
        var prop2 = list[i];
        this.checkPatternExport(exports, prop2);
      }
    } else if (type === "ArrayPattern") {
      for (var i$1 = 0, list$1 = pat.elements; i$1 < list$1.length; i$1 += 1) {
        var elt = list$1[i$1];
        if (elt) {
          this.checkPatternExport(exports, elt);
        }
      }
    } else if (type === "Property") {
      this.checkPatternExport(exports, pat.value);
    } else if (type === "AssignmentPattern") {
      this.checkPatternExport(exports, pat.left);
    } else if (type === "RestElement") {
      this.checkPatternExport(exports, pat.argument);
    }
  };
  pp$8.checkVariableExport = function(exports, decls) {
    if (!exports) {
      return;
    }
    for (var i = 0, list = decls; i < list.length; i += 1) {
      var decl = list[i];
      this.checkPatternExport(exports, decl.id);
    }
  };
  pp$8.shouldParseExportStatement = function() {
    return this.type.keyword === "var" || this.type.keyword === "const" || this.type.keyword === "class" || this.type.keyword === "function" || this.isLet() || this.isAsyncFunction();
  };
  pp$8.parseExportSpecifier = function(exports) {
    var node = this.startNode();
    node.local = this.parseModuleExportName();
    node.exported = this.eatContextual("as") ? this.parseModuleExportName() : node.local;
    this.checkExport(
      exports,
      node.exported,
      node.exported.start
    );
    return this.finishNode(node, "ExportSpecifier");
  };
  pp$8.parseExportSpecifiers = function(exports) {
    var nodes = [], first = true;
    this.expect(types$1.braceL);
    while (!this.eat(types$1.braceR)) {
      if (!first) {
        this.expect(types$1.comma);
        if (this.afterTrailingComma(types$1.braceR)) {
          break;
        }
      } else {
        first = false;
      }
      nodes.push(this.parseExportSpecifier(exports));
    }
    return nodes;
  };
  pp$8.parseImport = function(node) {
    this.next();
    if (this.type === types$1.string) {
      node.specifiers = empty$1;
      node.source = this.parseExprAtom();
    } else {
      node.specifiers = this.parseImportSpecifiers();
      this.expectContextual("from");
      node.source = this.type === types$1.string ? this.parseExprAtom() : this.unexpected();
    }
    if (this.options.ecmaVersion >= 16) {
      node.attributes = this.parseWithClause();
    }
    this.semicolon();
    return this.finishNode(node, "ImportDeclaration");
  };
  pp$8.parseImportSpecifier = function() {
    var node = this.startNode();
    node.imported = this.parseModuleExportName();
    if (this.eatContextual("as")) {
      node.local = this.parseIdent();
    } else {
      this.checkUnreserved(node.imported);
      node.local = node.imported;
    }
    this.checkLValSimple(node.local, BIND_LEXICAL);
    return this.finishNode(node, "ImportSpecifier");
  };
  pp$8.parseImportDefaultSpecifier = function() {
    var node = this.startNode();
    node.local = this.parseIdent();
    this.checkLValSimple(node.local, BIND_LEXICAL);
    return this.finishNode(node, "ImportDefaultSpecifier");
  };
  pp$8.parseImportNamespaceSpecifier = function() {
    var node = this.startNode();
    this.next();
    this.expectContextual("as");
    node.local = this.parseIdent();
    this.checkLValSimple(node.local, BIND_LEXICAL);
    return this.finishNode(node, "ImportNamespaceSpecifier");
  };
  pp$8.parseImportSpecifiers = function() {
    var nodes = [], first = true;
    if (this.type === types$1.name) {
      nodes.push(this.parseImportDefaultSpecifier());
      if (!this.eat(types$1.comma)) {
        return nodes;
      }
    }
    if (this.type === types$1.star) {
      nodes.push(this.parseImportNamespaceSpecifier());
      return nodes;
    }
    this.expect(types$1.braceL);
    while (!this.eat(types$1.braceR)) {
      if (!first) {
        this.expect(types$1.comma);
        if (this.afterTrailingComma(types$1.braceR)) {
          break;
        }
      } else {
        first = false;
      }
      nodes.push(this.parseImportSpecifier());
    }
    return nodes;
  };
  pp$8.parseWithClause = function() {
    var nodes = [];
    if (!this.eat(types$1._with)) {
      return nodes;
    }
    this.expect(types$1.braceL);
    var attributeKeys = {};
    var first = true;
    while (!this.eat(types$1.braceR)) {
      if (!first) {
        this.expect(types$1.comma);
        if (this.afterTrailingComma(types$1.braceR)) {
          break;
        }
      } else {
        first = false;
      }
      var attr = this.parseImportAttribute();
      var keyName = attr.key.type === "Identifier" ? attr.key.name : attr.key.value;
      if (hasOwn(attributeKeys, keyName)) {
        this.raiseRecoverable(attr.key.start, "Duplicate attribute key '" + keyName + "'");
      }
      attributeKeys[keyName] = true;
      nodes.push(attr);
    }
    return nodes;
  };
  pp$8.parseImportAttribute = function() {
    var node = this.startNode();
    node.key = this.type === types$1.string ? this.parseExprAtom() : this.parseIdent(this.options.allowReserved !== "never");
    this.expect(types$1.colon);
    if (this.type !== types$1.string) {
      this.unexpected();
    }
    node.value = this.parseExprAtom();
    return this.finishNode(node, "ImportAttribute");
  };
  pp$8.parseModuleExportName = function() {
    if (this.options.ecmaVersion >= 13 && this.type === types$1.string) {
      var stringLiteral = this.parseLiteral(this.value);
      if (loneSurrogate.test(stringLiteral.value)) {
        this.raise(stringLiteral.start, "An export name cannot include a lone surrogate.");
      }
      return stringLiteral;
    }
    return this.parseIdent(true);
  };
  pp$8.adaptDirectivePrologue = function(statements) {
    for (var i = 0; i < statements.length && this.isDirectiveCandidate(statements[i]); ++i) {
      statements[i].directive = statements[i].expression.raw.slice(1, -1);
    }
  };
  pp$8.isDirectiveCandidate = function(statement) {
    return this.options.ecmaVersion >= 5 && statement.type === "ExpressionStatement" && statement.expression.type === "Literal" && typeof statement.expression.value === "string" && // Reject parenthesized strings.
    (this.input[statement.start] === '"' || this.input[statement.start] === "'");
  };
  var pp$7 = Parser.prototype;
  pp$7.toAssignable = function(node, isBinding, refDestructuringErrors) {
    if (this.options.ecmaVersion >= 6 && node) {
      switch (node.type) {
        case "Identifier":
          if (this.inAsync && node.name === "await") {
            this.raise(node.start, "Cannot use 'await' as identifier inside an async function");
          }
          break;
        case "ObjectPattern":
        case "ArrayPattern":
        case "AssignmentPattern":
        case "RestElement":
          break;
        case "ObjectExpression":
          node.type = "ObjectPattern";
          if (refDestructuringErrors) {
            this.checkPatternErrors(refDestructuringErrors, true);
          }
          for (var i = 0, list = node.properties; i < list.length; i += 1) {
            var prop2 = list[i];
            this.toAssignable(prop2, isBinding);
            if (prop2.type === "RestElement" && (prop2.argument.type === "ArrayPattern" || prop2.argument.type === "ObjectPattern")) {
              this.raise(prop2.argument.start, "Unexpected token");
            }
          }
          break;
        case "Property":
          if (node.kind !== "init") {
            this.raise(node.key.start, "Object pattern can't contain getter or setter");
          }
          this.toAssignable(node.value, isBinding);
          break;
        case "ArrayExpression":
          node.type = "ArrayPattern";
          if (refDestructuringErrors) {
            this.checkPatternErrors(refDestructuringErrors, true);
          }
          this.toAssignableList(node.elements, isBinding);
          break;
        case "SpreadElement":
          node.type = "RestElement";
          this.toAssignable(node.argument, isBinding);
          if (node.argument.type === "AssignmentPattern") {
            this.raise(node.argument.start, "Rest elements cannot have a default value");
          }
          break;
        case "AssignmentExpression":
          if (node.operator !== "=") {
            this.raise(node.left.end, "Only '=' operator can be used for specifying default value.");
          }
          node.type = "AssignmentPattern";
          delete node.operator;
          this.toAssignable(node.left, isBinding);
          break;
        case "ParenthesizedExpression":
          this.toAssignable(node.expression, isBinding, refDestructuringErrors);
          break;
        case "ChainExpression":
          this.raiseRecoverable(node.start, "Optional chaining cannot appear in left-hand side");
          break;
        case "MemberExpression":
          if (!isBinding) {
            break;
          }
        default:
          this.raise(node.start, "Assigning to rvalue");
      }
    } else if (refDestructuringErrors) {
      this.checkPatternErrors(refDestructuringErrors, true);
    }
    return node;
  };
  pp$7.toAssignableList = function(exprList, isBinding) {
    var end = exprList.length;
    for (var i = 0; i < end; i++) {
      var elt = exprList[i];
      if (elt) {
        this.toAssignable(elt, isBinding);
      }
    }
    if (end) {
      var last = exprList[end - 1];
      if (this.options.ecmaVersion === 6 && isBinding && last && last.type === "RestElement" && last.argument.type !== "Identifier") {
        this.unexpected(last.argument.start);
      }
    }
    return exprList;
  };
  pp$7.parseSpread = function(refDestructuringErrors) {
    var node = this.startNode();
    this.next();
    node.argument = this.parseMaybeAssign(false, refDestructuringErrors);
    return this.finishNode(node, "SpreadElement");
  };
  pp$7.parseRestBinding = function() {
    var node = this.startNode();
    this.next();
    if (this.options.ecmaVersion === 6 && this.type !== types$1.name) {
      this.unexpected();
    }
    node.argument = this.parseBindingAtom();
    return this.finishNode(node, "RestElement");
  };
  pp$7.parseBindingAtom = function() {
    if (this.options.ecmaVersion >= 6) {
      switch (this.type) {
        case types$1.bracketL:
          var node = this.startNode();
          this.next();
          node.elements = this.parseBindingList(types$1.bracketR, true, true);
          return this.finishNode(node, "ArrayPattern");
        case types$1.braceL:
          return this.parseObj(true);
      }
    }
    return this.parseIdent();
  };
  pp$7.parseBindingList = function(close, allowEmpty, allowTrailingComma, allowModifiers) {
    var elts = [], first = true;
    while (!this.eat(close)) {
      if (first) {
        first = false;
      } else {
        this.expect(types$1.comma);
      }
      if (allowEmpty && this.type === types$1.comma) {
        elts.push(null);
      } else if (allowTrailingComma && this.afterTrailingComma(close)) {
        break;
      } else if (this.type === types$1.ellipsis) {
        var rest = this.parseRestBinding();
        this.parseBindingListItem(rest);
        elts.push(rest);
        if (this.type === types$1.comma) {
          this.raiseRecoverable(this.start, "Comma is not permitted after the rest element");
        }
        this.expect(close);
        break;
      } else {
        elts.push(this.parseAssignableListItem(allowModifiers));
      }
    }
    return elts;
  };
  pp$7.parseAssignableListItem = function(allowModifiers) {
    var elem = this.parseMaybeDefault(this.start, this.startLoc);
    this.parseBindingListItem(elem);
    return elem;
  };
  pp$7.parseBindingListItem = function(param) {
    return param;
  };
  pp$7.parseMaybeDefault = function(startPos, startLoc, left) {
    left = left || this.parseBindingAtom();
    if (this.options.ecmaVersion < 6 || !this.eat(types$1.eq)) {
      return left;
    }
    var node = this.startNodeAt(startPos, startLoc);
    node.left = left;
    node.right = this.parseMaybeAssign();
    return this.finishNode(node, "AssignmentPattern");
  };
  pp$7.checkLValSimple = function(expr, bindingType, checkClashes) {
    if (bindingType === void 0) bindingType = BIND_NONE;
    var isBind = bindingType !== BIND_NONE;
    switch (expr.type) {
      case "Identifier":
        if (this.strict && this.reservedWordsStrictBind.test(expr.name)) {
          this.raiseRecoverable(expr.start, (isBind ? "Binding " : "Assigning to ") + expr.name + " in strict mode");
        }
        if (isBind) {
          if (bindingType === BIND_LEXICAL && expr.name === "let") {
            this.raiseRecoverable(expr.start, "let is disallowed as a lexically bound name");
          }
          if (checkClashes) {
            if (hasOwn(checkClashes, expr.name)) {
              this.raiseRecoverable(expr.start, "Argument name clash");
            }
            checkClashes[expr.name] = true;
          }
          if (bindingType !== BIND_OUTSIDE) {
            this.declareName(expr.name, bindingType, expr.start);
          }
        }
        break;
      case "ChainExpression":
        this.raiseRecoverable(expr.start, "Optional chaining cannot appear in left-hand side");
        break;
      case "MemberExpression":
        if (isBind) {
          this.raiseRecoverable(expr.start, "Binding member expression");
        }
        break;
      case "ParenthesizedExpression":
        if (isBind) {
          this.raiseRecoverable(expr.start, "Binding parenthesized expression");
        }
        return this.checkLValSimple(expr.expression, bindingType, checkClashes);
      default:
        this.raise(expr.start, (isBind ? "Binding" : "Assigning to") + " rvalue");
    }
  };
  pp$7.checkLValPattern = function(expr, bindingType, checkClashes) {
    if (bindingType === void 0) bindingType = BIND_NONE;
    switch (expr.type) {
      case "ObjectPattern":
        for (var i = 0, list = expr.properties; i < list.length; i += 1) {
          var prop2 = list[i];
          this.checkLValInnerPattern(prop2, bindingType, checkClashes);
        }
        break;
      case "ArrayPattern":
        for (var i$1 = 0, list$1 = expr.elements; i$1 < list$1.length; i$1 += 1) {
          var elem = list$1[i$1];
          if (elem) {
            this.checkLValInnerPattern(elem, bindingType, checkClashes);
          }
        }
        break;
      default:
        this.checkLValSimple(expr, bindingType, checkClashes);
    }
  };
  pp$7.checkLValInnerPattern = function(expr, bindingType, checkClashes) {
    if (bindingType === void 0) bindingType = BIND_NONE;
    switch (expr.type) {
      case "Property":
        this.checkLValInnerPattern(expr.value, bindingType, checkClashes);
        break;
      case "AssignmentPattern":
        this.checkLValPattern(expr.left, bindingType, checkClashes);
        break;
      case "RestElement":
        this.checkLValPattern(expr.argument, bindingType, checkClashes);
        break;
      default:
        this.checkLValPattern(expr, bindingType, checkClashes);
    }
  };
  var TokContext = /* @__PURE__ */ __name(function TokContext2(token, isExpr, preserveSpace, override, generator) {
    this.token = token;
    this.isExpr = !!isExpr;
    this.preserveSpace = !!preserveSpace;
    this.override = override;
    this.generator = !!generator;
  }, "TokContext");
  var types = {
    b_stat: new TokContext("{", false),
    b_expr: new TokContext("{", true),
    b_tmpl: new TokContext("${", false),
    p_stat: new TokContext("(", false),
    p_expr: new TokContext("(", true),
    q_tmpl: new TokContext("`", true, true, function(p) {
      return p.tryReadTemplateToken();
    }),
    f_stat: new TokContext("function", false),
    f_expr: new TokContext("function", true),
    f_expr_gen: new TokContext("function", true, false, null, true),
    f_gen: new TokContext("function", false, false, null, true)
  };
  var pp$6 = Parser.prototype;
  pp$6.initialContext = function() {
    return [types.b_stat];
  };
  pp$6.curContext = function() {
    return this.context[this.context.length - 1];
  };
  pp$6.braceIsBlock = function(prevType) {
    var parent = this.curContext();
    if (parent === types.f_expr || parent === types.f_stat) {
      return true;
    }
    if (prevType === types$1.colon && (parent === types.b_stat || parent === types.b_expr)) {
      return !parent.isExpr;
    }
    if (prevType === types$1._return || prevType === types$1.name && this.exprAllowed) {
      return lineBreak.test(this.input.slice(this.lastTokEnd, this.start));
    }
    if (prevType === types$1._else || prevType === types$1.semi || prevType === types$1.eof || prevType === types$1.parenR || prevType === types$1.arrow) {
      return true;
    }
    if (prevType === types$1.braceL) {
      return parent === types.b_stat;
    }
    if (prevType === types$1._var || prevType === types$1._const || prevType === types$1.name) {
      return false;
    }
    return !this.exprAllowed;
  };
  pp$6.inGeneratorContext = function() {
    for (var i = this.context.length - 1; i >= 1; i--) {
      var context = this.context[i];
      if (context.token === "function") {
        return context.generator;
      }
    }
    return false;
  };
  pp$6.updateContext = function(prevType) {
    var update, type = this.type;
    if (type.keyword && prevType === types$1.dot) {
      this.exprAllowed = false;
    } else if (update = type.updateContext) {
      update.call(this, prevType);
    } else {
      this.exprAllowed = type.beforeExpr;
    }
  };
  pp$6.overrideContext = function(tokenCtx) {
    if (this.curContext() !== tokenCtx) {
      this.context[this.context.length - 1] = tokenCtx;
    }
  };
  types$1.parenR.updateContext = types$1.braceR.updateContext = function() {
    if (this.context.length === 1) {
      this.exprAllowed = true;
      return;
    }
    var out = this.context.pop();
    if (out === types.b_stat && this.curContext().token === "function") {
      out = this.context.pop();
    }
    this.exprAllowed = !out.isExpr;
  };
  types$1.braceL.updateContext = function(prevType) {
    this.context.push(this.braceIsBlock(prevType) ? types.b_stat : types.b_expr);
    this.exprAllowed = true;
  };
  types$1.dollarBraceL.updateContext = function() {
    this.context.push(types.b_tmpl);
    this.exprAllowed = true;
  };
  types$1.parenL.updateContext = function(prevType) {
    var statementParens = prevType === types$1._if || prevType === types$1._for || prevType === types$1._with || prevType === types$1._while;
    this.context.push(statementParens ? types.p_stat : types.p_expr);
    this.exprAllowed = true;
  };
  types$1.incDec.updateContext = function() {
  };
  types$1._function.updateContext = types$1._class.updateContext = function(prevType) {
    if (prevType.beforeExpr && prevType !== types$1._else && !(prevType === types$1.semi && this.curContext() !== types.p_stat) && !(prevType === types$1._return && lineBreak.test(this.input.slice(this.lastTokEnd, this.start))) && !((prevType === types$1.colon || prevType === types$1.braceL) && this.curContext() === types.b_stat)) {
      this.context.push(types.f_expr);
    } else {
      this.context.push(types.f_stat);
    }
    this.exprAllowed = false;
  };
  types$1.colon.updateContext = function() {
    if (this.curContext().token === "function") {
      this.context.pop();
    }
    this.exprAllowed = true;
  };
  types$1.backQuote.updateContext = function() {
    if (this.curContext() === types.q_tmpl) {
      this.context.pop();
    } else {
      this.context.push(types.q_tmpl);
    }
    this.exprAllowed = false;
  };
  types$1.star.updateContext = function(prevType) {
    if (prevType === types$1._function) {
      var index = this.context.length - 1;
      if (this.context[index] === types.f_expr) {
        this.context[index] = types.f_expr_gen;
      } else {
        this.context[index] = types.f_gen;
      }
    }
    this.exprAllowed = true;
  };
  types$1.name.updateContext = function(prevType) {
    var allowed = false;
    if (this.options.ecmaVersion >= 6 && prevType !== types$1.dot) {
      if (this.value === "of" && !this.exprAllowed || this.value === "yield" && this.inGeneratorContext()) {
        allowed = true;
      }
    }
    this.exprAllowed = allowed;
  };
  var pp$5 = Parser.prototype;
  pp$5.checkPropClash = function(prop2, propHash, refDestructuringErrors) {
    if (this.options.ecmaVersion >= 9 && prop2.type === "SpreadElement") {
      return;
    }
    if (this.options.ecmaVersion >= 6 && (prop2.computed || prop2.method || prop2.shorthand)) {
      return;
    }
    var key = prop2.key;
    var name;
    switch (key.type) {
      case "Identifier":
        name = key.name;
        break;
      case "Literal":
        name = String(key.value);
        break;
      default:
        return;
    }
    var kind = prop2.kind;
    if (this.options.ecmaVersion >= 6) {
      if (name === "__proto__" && kind === "init") {
        if (propHash.proto) {
          if (refDestructuringErrors) {
            if (refDestructuringErrors.doubleProto < 0) {
              refDestructuringErrors.doubleProto = key.start;
            }
          } else {
            this.raiseRecoverable(key.start, "Redefinition of __proto__ property");
          }
        }
        propHash.proto = true;
      }
      return;
    }
    name = "$" + name;
    var other = propHash[name];
    if (other) {
      var redefinition;
      if (kind === "init") {
        redefinition = this.strict && other.init || other.get || other.set;
      } else {
        redefinition = other.init || other[kind];
      }
      if (redefinition) {
        this.raiseRecoverable(key.start, "Redefinition of property");
      }
    } else {
      other = propHash[name] = {
        init: false,
        get: false,
        set: false
      };
    }
    other[kind] = true;
  };
  pp$5.parseExpression = function(forInit, refDestructuringErrors) {
    var startPos = this.start, startLoc = this.startLoc;
    var expr = this.parseMaybeAssign(forInit, refDestructuringErrors);
    if (this.type === types$1.comma) {
      var node = this.startNodeAt(startPos, startLoc);
      node.expressions = [expr];
      while (this.eat(types$1.comma)) {
        node.expressions.push(this.parseMaybeAssign(forInit, refDestructuringErrors));
      }
      return this.finishNode(node, "SequenceExpression");
    }
    return expr;
  };
  pp$5.parseMaybeAssign = function(forInit, refDestructuringErrors, afterLeftParse) {
    if (this.isContextual("yield")) {
      if (this.inGenerator) {
        return this.parseYield(forInit);
      } else {
        this.exprAllowed = false;
      }
    }
    var ownDestructuringErrors = false, oldParenAssign = -1, oldTrailingComma = -1, oldDoubleProto = -1;
    if (refDestructuringErrors) {
      oldParenAssign = refDestructuringErrors.parenthesizedAssign;
      oldTrailingComma = refDestructuringErrors.trailingComma;
      oldDoubleProto = refDestructuringErrors.doubleProto;
      refDestructuringErrors.parenthesizedAssign = refDestructuringErrors.trailingComma = -1;
    } else {
      refDestructuringErrors = new DestructuringErrors();
      ownDestructuringErrors = true;
    }
    var startPos = this.start, startLoc = this.startLoc;
    if (this.type === types$1.parenL || this.type === types$1.name) {
      this.potentialArrowAt = this.start;
      this.potentialArrowInForAwait = forInit === "await";
    }
    var left = this.parseMaybeConditional(forInit, refDestructuringErrors);
    if (afterLeftParse) {
      left = afterLeftParse.call(this, left, startPos, startLoc);
    }
    if (this.type.isAssign) {
      var node = this.startNodeAt(startPos, startLoc);
      node.operator = this.value;
      if (this.type === types$1.eq) {
        left = this.toAssignable(left, false, refDestructuringErrors);
      }
      if (!ownDestructuringErrors) {
        refDestructuringErrors.parenthesizedAssign = refDestructuringErrors.trailingComma = refDestructuringErrors.doubleProto = -1;
      }
      if (refDestructuringErrors.shorthandAssign >= left.start) {
        refDestructuringErrors.shorthandAssign = -1;
      }
      if (this.type === types$1.eq) {
        this.checkLValPattern(left);
      } else {
        this.checkLValSimple(left);
      }
      node.left = left;
      this.next();
      node.right = this.parseMaybeAssign(forInit);
      if (oldDoubleProto > -1) {
        refDestructuringErrors.doubleProto = oldDoubleProto;
      }
      return this.finishNode(node, "AssignmentExpression");
    } else {
      if (ownDestructuringErrors) {
        this.checkExpressionErrors(refDestructuringErrors, true);
      }
    }
    if (oldParenAssign > -1) {
      refDestructuringErrors.parenthesizedAssign = oldParenAssign;
    }
    if (oldTrailingComma > -1) {
      refDestructuringErrors.trailingComma = oldTrailingComma;
    }
    return left;
  };
  pp$5.parseMaybeConditional = function(forInit, refDestructuringErrors) {
    var startPos = this.start, startLoc = this.startLoc;
    var expr = this.parseExprOps(forInit, refDestructuringErrors);
    if (this.checkExpressionErrors(refDestructuringErrors)) {
      return expr;
    }
    if (this.eat(types$1.question)) {
      var node = this.startNodeAt(startPos, startLoc);
      node.test = expr;
      node.consequent = this.parseMaybeAssign();
      this.expect(types$1.colon);
      node.alternate = this.parseMaybeAssign(forInit);
      return this.finishNode(node, "ConditionalExpression");
    }
    return expr;
  };
  pp$5.parseExprOps = function(forInit, refDestructuringErrors) {
    var startPos = this.start, startLoc = this.startLoc;
    var expr = this.parseMaybeUnary(refDestructuringErrors, false, false, forInit);
    if (this.checkExpressionErrors(refDestructuringErrors)) {
      return expr;
    }
    return expr.start === startPos && expr.type === "ArrowFunctionExpression" ? expr : this.parseExprOp(expr, startPos, startLoc, -1, forInit);
  };
  pp$5.parseExprOp = function(left, leftStartPos, leftStartLoc, minPrec, forInit) {
    var prec = this.type.binop;
    if (prec != null && (!forInit || this.type !== types$1._in)) {
      if (prec > minPrec) {
        var logical = this.type === types$1.logicalOR || this.type === types$1.logicalAND;
        var coalesce = this.type === types$1.coalesce;
        if (coalesce) {
          prec = types$1.logicalAND.binop;
        }
        var op = this.value;
        this.next();
        var startPos = this.start, startLoc = this.startLoc;
        var right = this.parseExprOp(this.parseMaybeUnary(null, false, false, forInit), startPos, startLoc, prec, forInit);
        var node = this.buildBinary(leftStartPos, leftStartLoc, left, right, op, logical || coalesce);
        if (logical && this.type === types$1.coalesce || coalesce && (this.type === types$1.logicalOR || this.type === types$1.logicalAND)) {
          this.raiseRecoverable(this.start, "Logical expressions and coalesce expressions cannot be mixed. Wrap either by parentheses");
        }
        return this.parseExprOp(node, leftStartPos, leftStartLoc, minPrec, forInit);
      }
    }
    return left;
  };
  pp$5.buildBinary = function(startPos, startLoc, left, right, op, logical) {
    if (right.type === "PrivateIdentifier") {
      this.raise(right.start, "Private identifier can only be left side of binary expression");
    }
    var node = this.startNodeAt(startPos, startLoc);
    node.left = left;
    node.operator = op;
    node.right = right;
    return this.finishNode(node, logical ? "LogicalExpression" : "BinaryExpression");
  };
  pp$5.parseMaybeUnary = function(refDestructuringErrors, sawUnary, incDec, forInit) {
    var startPos = this.start, startLoc = this.startLoc, expr;
    if (this.isContextual("await") && this.canAwait) {
      expr = this.parseAwait(forInit);
      sawUnary = true;
    } else if (this.type.prefix) {
      var node = this.startNode(), update = this.type === types$1.incDec;
      node.operator = this.value;
      node.prefix = true;
      this.next();
      node.argument = this.parseMaybeUnary(null, true, update, forInit);
      this.checkExpressionErrors(refDestructuringErrors, true);
      if (update) {
        this.checkLValSimple(node.argument);
      } else if (this.strict && node.operator === "delete" && isLocalVariableAccess(node.argument)) {
        this.raiseRecoverable(node.start, "Deleting local variable in strict mode");
      } else if (node.operator === "delete" && isPrivateFieldAccess(node.argument)) {
        this.raiseRecoverable(node.start, "Private fields can not be deleted");
      } else {
        sawUnary = true;
      }
      expr = this.finishNode(node, update ? "UpdateExpression" : "UnaryExpression");
    } else if (!sawUnary && this.type === types$1.privateId) {
      if ((forInit || this.privateNameStack.length === 0) && this.options.checkPrivateFields) {
        this.unexpected();
      }
      expr = this.parsePrivateIdent();
      if (this.type !== types$1._in) {
        this.unexpected();
      }
    } else {
      expr = this.parseExprSubscripts(refDestructuringErrors, forInit);
      if (this.checkExpressionErrors(refDestructuringErrors)) {
        return expr;
      }
      while (this.type.postfix && !this.canInsertSemicolon()) {
        var node$1 = this.startNodeAt(startPos, startLoc);
        node$1.operator = this.value;
        node$1.prefix = false;
        node$1.argument = expr;
        this.checkLValSimple(expr);
        this.next();
        expr = this.finishNode(node$1, "UpdateExpression");
      }
    }
    if (!incDec && this.eat(types$1.starstar)) {
      if (sawUnary) {
        this.unexpected(this.lastTokStart);
      } else {
        return this.buildBinary(startPos, startLoc, expr, this.parseMaybeUnary(null, false, false, forInit), "**", false);
      }
    } else {
      return expr;
    }
  };
  function isLocalVariableAccess(node) {
    return node.type === "Identifier" || node.type === "ParenthesizedExpression" && isLocalVariableAccess(node.expression);
  }
  __name(isLocalVariableAccess, "isLocalVariableAccess");
  function isPrivateFieldAccess(node) {
    return node.type === "MemberExpression" && node.property.type === "PrivateIdentifier" || node.type === "ChainExpression" && isPrivateFieldAccess(node.expression) || node.type === "ParenthesizedExpression" && isPrivateFieldAccess(node.expression);
  }
  __name(isPrivateFieldAccess, "isPrivateFieldAccess");
  pp$5.parseExprSubscripts = function(refDestructuringErrors, forInit) {
    var startPos = this.start, startLoc = this.startLoc;
    var expr = this.parseExprAtom(refDestructuringErrors, forInit);
    if (expr.type === "ArrowFunctionExpression" && this.input.slice(this.lastTokStart, this.lastTokEnd) !== ")") {
      return expr;
    }
    var result = this.parseSubscripts(expr, startPos, startLoc, false, forInit);
    if (refDestructuringErrors && result.type === "MemberExpression") {
      if (refDestructuringErrors.parenthesizedAssign >= result.start) {
        refDestructuringErrors.parenthesizedAssign = -1;
      }
      if (refDestructuringErrors.parenthesizedBind >= result.start) {
        refDestructuringErrors.parenthesizedBind = -1;
      }
      if (refDestructuringErrors.trailingComma >= result.start) {
        refDestructuringErrors.trailingComma = -1;
      }
    }
    return result;
  };
  pp$5.parseSubscripts = function(base, startPos, startLoc, noCalls, forInit) {
    var maybeAsyncArrow = this.options.ecmaVersion >= 8 && base.type === "Identifier" && base.name === "async" && this.lastTokEnd === base.end && !this.canInsertSemicolon() && base.end - base.start === 5 && this.potentialArrowAt === base.start;
    var optionalChained = false;
    while (true) {
      var element = this.parseSubscript(base, startPos, startLoc, noCalls, maybeAsyncArrow, optionalChained, forInit);
      if (element.optional) {
        optionalChained = true;
      }
      if (element === base || element.type === "ArrowFunctionExpression") {
        if (optionalChained) {
          var chainNode = this.startNodeAt(startPos, startLoc);
          chainNode.expression = element;
          element = this.finishNode(chainNode, "ChainExpression");
        }
        return element;
      }
      base = element;
    }
  };
  pp$5.shouldParseAsyncArrow = function() {
    return !this.canInsertSemicolon() && this.eat(types$1.arrow);
  };
  pp$5.parseSubscriptAsyncArrow = function(startPos, startLoc, exprList, forInit) {
    return this.parseArrowExpression(this.startNodeAt(startPos, startLoc), exprList, true, forInit);
  };
  pp$5.parseSubscript = function(base, startPos, startLoc, noCalls, maybeAsyncArrow, optionalChained, forInit) {
    var optionalSupported = this.options.ecmaVersion >= 11;
    var optional = optionalSupported && this.eat(types$1.questionDot);
    if (noCalls && optional) {
      this.raise(this.lastTokStart, "Optional chaining cannot appear in the callee of new expressions");
    }
    var computed = this.eat(types$1.bracketL);
    if (computed || optional && this.type !== types$1.parenL && this.type !== types$1.backQuote || this.eat(types$1.dot)) {
      var node = this.startNodeAt(startPos, startLoc);
      node.object = base;
      if (computed) {
        node.property = this.parseExpression();
        this.expect(types$1.bracketR);
      } else if (this.type === types$1.privateId && base.type !== "Super") {
        node.property = this.parsePrivateIdent();
      } else {
        node.property = this.parseIdent(this.options.allowReserved !== "never");
      }
      node.computed = !!computed;
      if (optionalSupported) {
        node.optional = optional;
      }
      base = this.finishNode(node, "MemberExpression");
    } else if (!noCalls && this.eat(types$1.parenL)) {
      var refDestructuringErrors = new DestructuringErrors(), oldYieldPos = this.yieldPos, oldAwaitPos = this.awaitPos, oldAwaitIdentPos = this.awaitIdentPos;
      this.yieldPos = 0;
      this.awaitPos = 0;
      this.awaitIdentPos = 0;
      var exprList = this.parseExprList(types$1.parenR, this.options.ecmaVersion >= 8, false, refDestructuringErrors);
      if (maybeAsyncArrow && !optional && this.shouldParseAsyncArrow()) {
        this.checkPatternErrors(refDestructuringErrors, false);
        this.checkYieldAwaitInDefaultParams();
        if (this.awaitIdentPos > 0) {
          this.raise(this.awaitIdentPos, "Cannot use 'await' as identifier inside an async function");
        }
        this.yieldPos = oldYieldPos;
        this.awaitPos = oldAwaitPos;
        this.awaitIdentPos = oldAwaitIdentPos;
        return this.parseSubscriptAsyncArrow(startPos, startLoc, exprList, forInit);
      }
      this.checkExpressionErrors(refDestructuringErrors, true);
      this.yieldPos = oldYieldPos || this.yieldPos;
      this.awaitPos = oldAwaitPos || this.awaitPos;
      this.awaitIdentPos = oldAwaitIdentPos || this.awaitIdentPos;
      var node$1 = this.startNodeAt(startPos, startLoc);
      node$1.callee = base;
      node$1.arguments = exprList;
      if (optionalSupported) {
        node$1.optional = optional;
      }
      base = this.finishNode(node$1, "CallExpression");
    } else if (this.type === types$1.backQuote) {
      if (optional || optionalChained) {
        this.raise(this.start, "Optional chaining cannot appear in the tag of tagged template expressions");
      }
      var node$2 = this.startNodeAt(startPos, startLoc);
      node$2.tag = base;
      node$2.quasi = this.parseTemplate({ isTagged: true });
      base = this.finishNode(node$2, "TaggedTemplateExpression");
    }
    return base;
  };
  pp$5.parseExprAtom = function(refDestructuringErrors, forInit, forNew) {
    if (this.type === types$1.slash) {
      this.readRegexp();
    }
    var node, canBeArrow = this.potentialArrowAt === this.start;
    switch (this.type) {
      case types$1._super:
        if (!this.allowSuper) {
          this.raise(this.start, "'super' keyword outside a method");
        }
        node = this.startNode();
        this.next();
        if (this.type === types$1.parenL && !this.allowDirectSuper) {
          this.raise(node.start, "super() call outside constructor of a subclass");
        }
        if (this.type !== types$1.dot && this.type !== types$1.bracketL && this.type !== types$1.parenL) {
          this.unexpected();
        }
        return this.finishNode(node, "Super");
      case types$1._this:
        node = this.startNode();
        this.next();
        return this.finishNode(node, "ThisExpression");
      case types$1.name:
        var startPos = this.start, startLoc = this.startLoc, containsEsc = this.containsEsc;
        var id = this.parseIdent(false);
        if (this.options.ecmaVersion >= 8 && !containsEsc && id.name === "async" && !this.canInsertSemicolon() && this.eat(types$1._function)) {
          this.overrideContext(types.f_expr);
          return this.parseFunction(this.startNodeAt(startPos, startLoc), 0, false, true, forInit);
        }
        if (canBeArrow && !this.canInsertSemicolon()) {
          if (this.eat(types$1.arrow)) {
            return this.parseArrowExpression(this.startNodeAt(startPos, startLoc), [id], false, forInit);
          }
          if (this.options.ecmaVersion >= 8 && id.name === "async" && this.type === types$1.name && !containsEsc && (!this.potentialArrowInForAwait || this.value !== "of" || this.containsEsc)) {
            id = this.parseIdent(false);
            if (this.canInsertSemicolon() || !this.eat(types$1.arrow)) {
              this.unexpected();
            }
            return this.parseArrowExpression(this.startNodeAt(startPos, startLoc), [id], true, forInit);
          }
        }
        return id;
      case types$1.regexp:
        var value = this.value;
        node = this.parseLiteral(value.value);
        node.regex = { pattern: value.pattern, flags: value.flags };
        return node;
      case types$1.num:
      case types$1.string:
        return this.parseLiteral(this.value);
      case types$1._null:
      case types$1._true:
      case types$1._false:
        node = this.startNode();
        node.value = this.type === types$1._null ? null : this.type === types$1._true;
        node.raw = this.type.keyword;
        this.next();
        return this.finishNode(node, "Literal");
      case types$1.parenL:
        var start2 = this.start, expr = this.parseParenAndDistinguishExpression(canBeArrow, forInit);
        if (refDestructuringErrors) {
          if (refDestructuringErrors.parenthesizedAssign < 0 && !this.isSimpleAssignTarget(expr)) {
            refDestructuringErrors.parenthesizedAssign = start2;
          }
          if (refDestructuringErrors.parenthesizedBind < 0) {
            refDestructuringErrors.parenthesizedBind = start2;
          }
        }
        return expr;
      case types$1.bracketL:
        node = this.startNode();
        this.next();
        node.elements = this.parseExprList(types$1.bracketR, true, true, refDestructuringErrors);
        return this.finishNode(node, "ArrayExpression");
      case types$1.braceL:
        this.overrideContext(types.b_expr);
        return this.parseObj(false, refDestructuringErrors);
      case types$1._function:
        node = this.startNode();
        this.next();
        return this.parseFunction(node, 0);
      case types$1._class:
        return this.parseClass(this.startNode(), false);
      case types$1._new:
        return this.parseNew();
      case types$1.backQuote:
        return this.parseTemplate();
      case types$1._import:
        if (this.options.ecmaVersion >= 11) {
          return this.parseExprImport(forNew);
        } else {
          return this.unexpected();
        }
      default:
        return this.parseExprAtomDefault();
    }
  };
  pp$5.parseExprAtomDefault = function() {
    this.unexpected();
  };
  pp$5.parseExprImport = function(forNew) {
    var node = this.startNode();
    if (this.containsEsc) {
      this.raiseRecoverable(this.start, "Escape sequence in keyword import");
    }
    this.next();
    if (this.type === types$1.parenL && !forNew) {
      return this.parseDynamicImport(node);
    } else if (this.type === types$1.dot) {
      var meta = this.startNodeAt(node.start, node.loc && node.loc.start);
      meta.name = "import";
      node.meta = this.finishNode(meta, "Identifier");
      return this.parseImportMeta(node);
    } else {
      this.unexpected();
    }
  };
  pp$5.parseDynamicImport = function(node) {
    this.next();
    node.source = this.parseMaybeAssign();
    if (this.options.ecmaVersion >= 16) {
      if (!this.eat(types$1.parenR)) {
        this.expect(types$1.comma);
        if (!this.afterTrailingComma(types$1.parenR)) {
          node.options = this.parseMaybeAssign();
          if (!this.eat(types$1.parenR)) {
            this.expect(types$1.comma);
            if (!this.afterTrailingComma(types$1.parenR)) {
              this.unexpected();
            }
          }
        } else {
          node.options = null;
        }
      } else {
        node.options = null;
      }
    } else {
      if (!this.eat(types$1.parenR)) {
        var errorPos = this.start;
        if (this.eat(types$1.comma) && this.eat(types$1.parenR)) {
          this.raiseRecoverable(errorPos, "Trailing comma is not allowed in import()");
        } else {
          this.unexpected(errorPos);
        }
      }
    }
    return this.finishNode(node, "ImportExpression");
  };
  pp$5.parseImportMeta = function(node) {
    this.next();
    var containsEsc = this.containsEsc;
    node.property = this.parseIdent(true);
    if (node.property.name !== "meta") {
      this.raiseRecoverable(node.property.start, "The only valid meta property for import is 'import.meta'");
    }
    if (containsEsc) {
      this.raiseRecoverable(node.start, "'import.meta' must not contain escaped characters");
    }
    if (this.options.sourceType !== "module" && !this.options.allowImportExportEverywhere) {
      this.raiseRecoverable(node.start, "Cannot use 'import.meta' outside a module");
    }
    return this.finishNode(node, "MetaProperty");
  };
  pp$5.parseLiteral = function(value) {
    var node = this.startNode();
    node.value = value;
    node.raw = this.input.slice(this.start, this.end);
    if (node.raw.charCodeAt(node.raw.length - 1) === 110) {
      node.bigint = node.value != null ? node.value.toString() : node.raw.slice(0, -1).replace(/_/g, "");
    }
    this.next();
    return this.finishNode(node, "Literal");
  };
  pp$5.parseParenExpression = function() {
    this.expect(types$1.parenL);
    var val = this.parseExpression();
    this.expect(types$1.parenR);
    return val;
  };
  pp$5.shouldParseArrow = function(exprList) {
    return !this.canInsertSemicolon();
  };
  pp$5.parseParenAndDistinguishExpression = function(canBeArrow, forInit) {
    var startPos = this.start, startLoc = this.startLoc, val, allowTrailingComma = this.options.ecmaVersion >= 8;
    if (this.options.ecmaVersion >= 6) {
      this.next();
      var innerStartPos = this.start, innerStartLoc = this.startLoc;
      var exprList = [], first = true, lastIsComma = false;
      var refDestructuringErrors = new DestructuringErrors(), oldYieldPos = this.yieldPos, oldAwaitPos = this.awaitPos, spreadStart;
      this.yieldPos = 0;
      this.awaitPos = 0;
      while (this.type !== types$1.parenR) {
        first ? first = false : this.expect(types$1.comma);
        if (allowTrailingComma && this.afterTrailingComma(types$1.parenR, true)) {
          lastIsComma = true;
          break;
        } else if (this.type === types$1.ellipsis) {
          spreadStart = this.start;
          exprList.push(this.parseParenItem(this.parseRestBinding()));
          if (this.type === types$1.comma) {
            this.raiseRecoverable(
              this.start,
              "Comma is not permitted after the rest element"
            );
          }
          break;
        } else {
          exprList.push(this.parseMaybeAssign(false, refDestructuringErrors, this.parseParenItem));
        }
      }
      var innerEndPos = this.lastTokEnd, innerEndLoc = this.lastTokEndLoc;
      this.expect(types$1.parenR);
      if (canBeArrow && this.shouldParseArrow(exprList) && this.eat(types$1.arrow)) {
        this.checkPatternErrors(refDestructuringErrors, false);
        this.checkYieldAwaitInDefaultParams();
        this.yieldPos = oldYieldPos;
        this.awaitPos = oldAwaitPos;
        return this.parseParenArrowList(startPos, startLoc, exprList, forInit);
      }
      if (!exprList.length || lastIsComma) {
        this.unexpected(this.lastTokStart);
      }
      if (spreadStart) {
        this.unexpected(spreadStart);
      }
      this.checkExpressionErrors(refDestructuringErrors, true);
      this.yieldPos = oldYieldPos || this.yieldPos;
      this.awaitPos = oldAwaitPos || this.awaitPos;
      if (exprList.length > 1) {
        val = this.startNodeAt(innerStartPos, innerStartLoc);
        val.expressions = exprList;
        this.finishNodeAt(val, "SequenceExpression", innerEndPos, innerEndLoc);
      } else {
        val = exprList[0];
      }
    } else {
      val = this.parseParenExpression();
    }
    if (this.options.preserveParens) {
      var par = this.startNodeAt(startPos, startLoc);
      par.expression = val;
      return this.finishNode(par, "ParenthesizedExpression");
    } else {
      return val;
    }
  };
  pp$5.parseParenItem = function(item) {
    return item;
  };
  pp$5.parseParenArrowList = function(startPos, startLoc, exprList, forInit) {
    return this.parseArrowExpression(this.startNodeAt(startPos, startLoc), exprList, false, forInit);
  };
  var empty = [];
  pp$5.parseNew = function() {
    if (this.containsEsc) {
      this.raiseRecoverable(this.start, "Escape sequence in keyword new");
    }
    var node = this.startNode();
    this.next();
    if (this.options.ecmaVersion >= 6 && this.type === types$1.dot) {
      var meta = this.startNodeAt(node.start, node.loc && node.loc.start);
      meta.name = "new";
      node.meta = this.finishNode(meta, "Identifier");
      this.next();
      var containsEsc = this.containsEsc;
      node.property = this.parseIdent(true);
      if (node.property.name !== "target") {
        this.raiseRecoverable(node.property.start, "The only valid meta property for new is 'new.target'");
      }
      if (containsEsc) {
        this.raiseRecoverable(node.start, "'new.target' must not contain escaped characters");
      }
      if (!this.allowNewDotTarget) {
        this.raiseRecoverable(node.start, "'new.target' can only be used in functions and class static block");
      }
      return this.finishNode(node, "MetaProperty");
    }
    var startPos = this.start, startLoc = this.startLoc;
    node.callee = this.parseSubscripts(this.parseExprAtom(null, false, true), startPos, startLoc, true, false);
    if (this.eat(types$1.parenL)) {
      node.arguments = this.parseExprList(types$1.parenR, this.options.ecmaVersion >= 8, false);
    } else {
      node.arguments = empty;
    }
    return this.finishNode(node, "NewExpression");
  };
  pp$5.parseTemplateElement = function(ref2) {
    var isTagged = ref2.isTagged;
    var elem = this.startNode();
    if (this.type === types$1.invalidTemplate) {
      if (!isTagged) {
        this.raiseRecoverable(this.start, "Bad escape sequence in untagged template literal");
      }
      elem.value = {
        raw: this.value.replace(/\r\n?/g, "\n"),
        cooked: null
      };
    } else {
      elem.value = {
        raw: this.input.slice(this.start, this.end).replace(/\r\n?/g, "\n"),
        cooked: this.value
      };
    }
    this.next();
    elem.tail = this.type === types$1.backQuote;
    return this.finishNode(elem, "TemplateElement");
  };
  pp$5.parseTemplate = function(ref2) {
    if (ref2 === void 0) ref2 = {};
    var isTagged = ref2.isTagged;
    if (isTagged === void 0) isTagged = false;
    var node = this.startNode();
    this.next();
    node.expressions = [];
    var curElt = this.parseTemplateElement({ isTagged });
    node.quasis = [curElt];
    while (!curElt.tail) {
      if (this.type === types$1.eof) {
        this.raise(this.pos, "Unterminated template literal");
      }
      this.expect(types$1.dollarBraceL);
      node.expressions.push(this.parseExpression());
      this.expect(types$1.braceR);
      node.quasis.push(curElt = this.parseTemplateElement({ isTagged }));
    }
    this.next();
    return this.finishNode(node, "TemplateLiteral");
  };
  pp$5.isAsyncProp = function(prop2) {
    return !prop2.computed && prop2.key.type === "Identifier" && prop2.key.name === "async" && (this.type === types$1.name || this.type === types$1.num || this.type === types$1.string || this.type === types$1.bracketL || this.type.keyword || this.options.ecmaVersion >= 9 && this.type === types$1.star) && !lineBreak.test(this.input.slice(this.lastTokEnd, this.start));
  };
  pp$5.parseObj = function(isPattern, refDestructuringErrors) {
    var node = this.startNode(), first = true, propHash = {};
    node.properties = [];
    this.next();
    while (!this.eat(types$1.braceR)) {
      if (!first) {
        this.expect(types$1.comma);
        if (this.options.ecmaVersion >= 5 && this.afterTrailingComma(types$1.braceR)) {
          break;
        }
      } else {
        first = false;
      }
      var prop2 = this.parseProperty(isPattern, refDestructuringErrors);
      if (!isPattern) {
        this.checkPropClash(prop2, propHash, refDestructuringErrors);
      }
      node.properties.push(prop2);
    }
    return this.finishNode(node, isPattern ? "ObjectPattern" : "ObjectExpression");
  };
  pp$5.parseProperty = function(isPattern, refDestructuringErrors) {
    var prop2 = this.startNode(), isGenerator, isAsync, startPos, startLoc;
    if (this.options.ecmaVersion >= 9 && this.eat(types$1.ellipsis)) {
      if (isPattern) {
        prop2.argument = this.parseIdent(false);
        if (this.type === types$1.comma) {
          this.raiseRecoverable(this.start, "Comma is not permitted after the rest element");
        }
        return this.finishNode(prop2, "RestElement");
      }
      prop2.argument = this.parseMaybeAssign(false, refDestructuringErrors);
      if (this.type === types$1.comma && refDestructuringErrors && refDestructuringErrors.trailingComma < 0) {
        refDestructuringErrors.trailingComma = this.start;
      }
      return this.finishNode(prop2, "SpreadElement");
    }
    if (this.options.ecmaVersion >= 6) {
      prop2.method = false;
      prop2.shorthand = false;
      if (isPattern || refDestructuringErrors) {
        startPos = this.start;
        startLoc = this.startLoc;
      }
      if (!isPattern) {
        isGenerator = this.eat(types$1.star);
      }
    }
    var containsEsc = this.containsEsc;
    this.parsePropertyName(prop2);
    if (!isPattern && !containsEsc && this.options.ecmaVersion >= 8 && !isGenerator && this.isAsyncProp(prop2)) {
      isAsync = true;
      isGenerator = this.options.ecmaVersion >= 9 && this.eat(types$1.star);
      this.parsePropertyName(prop2);
    } else {
      isAsync = false;
    }
    this.parsePropertyValue(prop2, isPattern, isGenerator, isAsync, startPos, startLoc, refDestructuringErrors, containsEsc);
    return this.finishNode(prop2, "Property");
  };
  pp$5.parseGetterSetter = function(prop2) {
    var kind = prop2.key.name;
    this.parsePropertyName(prop2);
    prop2.value = this.parseMethod(false);
    prop2.kind = kind;
    var paramCount = prop2.kind === "get" ? 0 : 1;
    if (prop2.value.params.length !== paramCount) {
      var start2 = prop2.value.start;
      if (prop2.kind === "get") {
        this.raiseRecoverable(start2, "getter should have no params");
      } else {
        this.raiseRecoverable(start2, "setter should have exactly one param");
      }
    } else {
      if (prop2.kind === "set" && prop2.value.params[0].type === "RestElement") {
        this.raiseRecoverable(prop2.value.params[0].start, "Setter cannot use rest params");
      }
    }
  };
  pp$5.parsePropertyValue = function(prop2, isPattern, isGenerator, isAsync, startPos, startLoc, refDestructuringErrors, containsEsc) {
    if ((isGenerator || isAsync) && this.type === types$1.colon) {
      this.unexpected();
    }
    if (this.eat(types$1.colon)) {
      prop2.value = isPattern ? this.parseMaybeDefault(this.start, this.startLoc) : this.parseMaybeAssign(false, refDestructuringErrors);
      prop2.kind = "init";
    } else if (this.options.ecmaVersion >= 6 && this.type === types$1.parenL) {
      if (isPattern) {
        this.unexpected();
      }
      prop2.method = true;
      prop2.value = this.parseMethod(isGenerator, isAsync);
      prop2.kind = "init";
    } else if (!isPattern && !containsEsc && this.options.ecmaVersion >= 5 && !prop2.computed && prop2.key.type === "Identifier" && (prop2.key.name === "get" || prop2.key.name === "set") && (this.type !== types$1.comma && this.type !== types$1.braceR && this.type !== types$1.eq)) {
      if (isGenerator || isAsync) {
        this.unexpected();
      }
      this.parseGetterSetter(prop2);
    } else if (this.options.ecmaVersion >= 6 && !prop2.computed && prop2.key.type === "Identifier") {
      if (isGenerator || isAsync) {
        this.unexpected();
      }
      this.checkUnreserved(prop2.key);
      if (prop2.key.name === "await" && !this.awaitIdentPos) {
        this.awaitIdentPos = startPos;
      }
      if (isPattern) {
        prop2.value = this.parseMaybeDefault(startPos, startLoc, this.copyNode(prop2.key));
      } else if (this.type === types$1.eq && refDestructuringErrors) {
        if (refDestructuringErrors.shorthandAssign < 0) {
          refDestructuringErrors.shorthandAssign = this.start;
        }
        prop2.value = this.parseMaybeDefault(startPos, startLoc, this.copyNode(prop2.key));
      } else {
        prop2.value = this.copyNode(prop2.key);
      }
      prop2.kind = "init";
      prop2.shorthand = true;
    } else {
      this.unexpected();
    }
  };
  pp$5.parsePropertyName = function(prop2) {
    if (this.options.ecmaVersion >= 6) {
      if (this.eat(types$1.bracketL)) {
        prop2.computed = true;
        prop2.key = this.parseMaybeAssign();
        this.expect(types$1.bracketR);
        return prop2.key;
      } else {
        prop2.computed = false;
      }
    }
    return prop2.key = this.type === types$1.num || this.type === types$1.string ? this.parseExprAtom() : this.parseIdent(this.options.allowReserved !== "never");
  };
  pp$5.initFunction = function(node) {
    node.id = null;
    if (this.options.ecmaVersion >= 6) {
      node.generator = node.expression = false;
    }
    if (this.options.ecmaVersion >= 8) {
      node.async = false;
    }
  };
  pp$5.parseMethod = function(isGenerator, isAsync, allowDirectSuper) {
    var node = this.startNode(), oldYieldPos = this.yieldPos, oldAwaitPos = this.awaitPos, oldAwaitIdentPos = this.awaitIdentPos;
    this.initFunction(node);
    if (this.options.ecmaVersion >= 6) {
      node.generator = isGenerator;
    }
    if (this.options.ecmaVersion >= 8) {
      node.async = !!isAsync;
    }
    this.yieldPos = 0;
    this.awaitPos = 0;
    this.awaitIdentPos = 0;
    this.enterScope(functionFlags(isAsync, node.generator) | SCOPE_SUPER | (allowDirectSuper ? SCOPE_DIRECT_SUPER : 0));
    this.expect(types$1.parenL);
    node.params = this.parseBindingList(types$1.parenR, false, this.options.ecmaVersion >= 8);
    this.checkYieldAwaitInDefaultParams();
    this.parseFunctionBody(node, false, true, false);
    this.yieldPos = oldYieldPos;
    this.awaitPos = oldAwaitPos;
    this.awaitIdentPos = oldAwaitIdentPos;
    return this.finishNode(node, "FunctionExpression");
  };
  pp$5.parseArrowExpression = function(node, params, isAsync, forInit) {
    var oldYieldPos = this.yieldPos, oldAwaitPos = this.awaitPos, oldAwaitIdentPos = this.awaitIdentPos;
    this.enterScope(functionFlags(isAsync, false) | SCOPE_ARROW);
    this.initFunction(node);
    if (this.options.ecmaVersion >= 8) {
      node.async = !!isAsync;
    }
    this.yieldPos = 0;
    this.awaitPos = 0;
    this.awaitIdentPos = 0;
    node.params = this.toAssignableList(params, true);
    this.parseFunctionBody(node, true, false, forInit);
    this.yieldPos = oldYieldPos;
    this.awaitPos = oldAwaitPos;
    this.awaitIdentPos = oldAwaitIdentPos;
    return this.finishNode(node, "ArrowFunctionExpression");
  };
  pp$5.parseFunctionBody = function(node, isArrowFunction, isMethod, forInit) {
    var isExpression = isArrowFunction && this.type !== types$1.braceL;
    var oldStrict = this.strict, useStrict = false;
    if (isExpression) {
      node.body = this.parseMaybeAssign(forInit);
      node.expression = true;
      this.checkParams(node, false);
    } else {
      var nonSimple = this.options.ecmaVersion >= 7 && !this.isSimpleParamList(node.params);
      if (!oldStrict || nonSimple) {
        useStrict = this.strictDirective(this.end);
        if (useStrict && nonSimple) {
          this.raiseRecoverable(node.start, "Illegal 'use strict' directive in function with non-simple parameter list");
        }
      }
      var oldLabels = this.labels;
      this.labels = [];
      if (useStrict) {
        this.strict = true;
      }
      this.checkParams(node, !oldStrict && !useStrict && !isArrowFunction && !isMethod && this.isSimpleParamList(node.params));
      if (this.strict && node.id) {
        this.checkLValSimple(node.id, BIND_OUTSIDE);
      }
      node.body = this.parseBlock(false, void 0, useStrict && !oldStrict);
      node.expression = false;
      this.adaptDirectivePrologue(node.body.body);
      this.labels = oldLabels;
    }
    this.exitScope();
  };
  pp$5.isSimpleParamList = function(params) {
    for (var i = 0, list = params; i < list.length; i += 1) {
      var param = list[i];
      if (param.type !== "Identifier") {
        return false;
      }
    }
    return true;
  };
  pp$5.checkParams = function(node, allowDuplicates) {
    var nameHash = /* @__PURE__ */ Object.create(null);
    for (var i = 0, list = node.params; i < list.length; i += 1) {
      var param = list[i];
      this.checkLValInnerPattern(param, BIND_VAR, allowDuplicates ? null : nameHash);
    }
  };
  pp$5.parseExprList = function(close, allowTrailingComma, allowEmpty, refDestructuringErrors) {
    var elts = [], first = true;
    while (!this.eat(close)) {
      if (!first) {
        this.expect(types$1.comma);
        if (allowTrailingComma && this.afterTrailingComma(close)) {
          break;
        }
      } else {
        first = false;
      }
      var elt = void 0;
      if (allowEmpty && this.type === types$1.comma) {
        elt = null;
      } else if (this.type === types$1.ellipsis) {
        elt = this.parseSpread(refDestructuringErrors);
        if (refDestructuringErrors && this.type === types$1.comma && refDestructuringErrors.trailingComma < 0) {
          refDestructuringErrors.trailingComma = this.start;
        }
      } else {
        elt = this.parseMaybeAssign(false, refDestructuringErrors);
      }
      elts.push(elt);
    }
    return elts;
  };
  pp$5.checkUnreserved = function(ref2) {
    var start2 = ref2.start;
    var end = ref2.end;
    var name = ref2.name;
    if (this.inGenerator && name === "yield") {
      this.raiseRecoverable(start2, "Cannot use 'yield' as identifier inside a generator");
    }
    if (this.inAsync && name === "await") {
      this.raiseRecoverable(start2, "Cannot use 'await' as identifier inside an async function");
    }
    if (!(this.currentThisScope().flags & SCOPE_VAR) && name === "arguments") {
      this.raiseRecoverable(start2, "Cannot use 'arguments' in class field initializer");
    }
    if (this.inClassStaticBlock && (name === "arguments" || name === "await")) {
      this.raise(start2, "Cannot use " + name + " in class static initialization block");
    }
    if (this.keywords.test(name)) {
      this.raise(start2, "Unexpected keyword '" + name + "'");
    }
    if (this.options.ecmaVersion < 6 && this.input.slice(start2, end).indexOf("\\") !== -1) {
      return;
    }
    var re = this.strict ? this.reservedWordsStrict : this.reservedWords;
    if (re.test(name)) {
      if (!this.inAsync && name === "await") {
        this.raiseRecoverable(start2, "Cannot use keyword 'await' outside an async function");
      }
      this.raiseRecoverable(start2, "The keyword '" + name + "' is reserved");
    }
  };
  pp$5.parseIdent = function(liberal) {
    var node = this.parseIdentNode();
    this.next(!!liberal);
    this.finishNode(node, "Identifier");
    if (!liberal) {
      this.checkUnreserved(node);
      if (node.name === "await" && !this.awaitIdentPos) {
        this.awaitIdentPos = node.start;
      }
    }
    return node;
  };
  pp$5.parseIdentNode = function() {
    var node = this.startNode();
    if (this.type === types$1.name) {
      node.name = this.value;
    } else if (this.type.keyword) {
      node.name = this.type.keyword;
      if ((node.name === "class" || node.name === "function") && (this.lastTokEnd !== this.lastTokStart + 1 || this.input.charCodeAt(this.lastTokStart) !== 46)) {
        this.context.pop();
      }
      this.type = types$1.name;
    } else {
      this.unexpected();
    }
    return node;
  };
  pp$5.parsePrivateIdent = function() {
    var node = this.startNode();
    if (this.type === types$1.privateId) {
      node.name = this.value;
    } else {
      this.unexpected();
    }
    this.next();
    this.finishNode(node, "PrivateIdentifier");
    if (this.options.checkPrivateFields) {
      if (this.privateNameStack.length === 0) {
        this.raise(node.start, "Private field '#" + node.name + "' must be declared in an enclosing class");
      } else {
        this.privateNameStack[this.privateNameStack.length - 1].used.push(node);
      }
    }
    return node;
  };
  pp$5.parseYield = function(forInit) {
    if (!this.yieldPos) {
      this.yieldPos = this.start;
    }
    var node = this.startNode();
    this.next();
    if (this.type === types$1.semi || this.canInsertSemicolon() || this.type !== types$1.star && !this.type.startsExpr) {
      node.delegate = false;
      node.argument = null;
    } else {
      node.delegate = this.eat(types$1.star);
      node.argument = this.parseMaybeAssign(forInit);
    }
    return this.finishNode(node, "YieldExpression");
  };
  pp$5.parseAwait = function(forInit) {
    if (!this.awaitPos) {
      this.awaitPos = this.start;
    }
    var node = this.startNode();
    this.next();
    node.argument = this.parseMaybeUnary(null, true, false, forInit);
    return this.finishNode(node, "AwaitExpression");
  };
  var pp$4 = Parser.prototype;
  pp$4.raise = function(pos, message) {
    var loc = getLineInfo(this.input, pos);
    message += " (" + loc.line + ":" + loc.column + ")";
    if (this.sourceFile) {
      message += " in " + this.sourceFile;
    }
    var err = new SyntaxError(message);
    err.pos = pos;
    err.loc = loc;
    err.raisedAt = this.pos;
    throw err;
  };
  pp$4.raiseRecoverable = pp$4.raise;
  pp$4.curPosition = function() {
    if (this.options.locations) {
      return new Position(this.curLine, this.pos - this.lineStart);
    }
  };
  var pp$3 = Parser.prototype;
  var Scope = /* @__PURE__ */ __name(function Scope2(flags) {
    this.flags = flags;
    this.var = [];
    this.lexical = [];
    this.functions = [];
  }, "Scope");
  pp$3.enterScope = function(flags) {
    this.scopeStack.push(new Scope(flags));
  };
  pp$3.exitScope = function() {
    this.scopeStack.pop();
  };
  pp$3.treatFunctionsAsVarInScope = function(scope) {
    return scope.flags & SCOPE_FUNCTION || !this.inModule && scope.flags & SCOPE_TOP;
  };
  pp$3.declareName = function(name, bindingType, pos) {
    var redeclared = false;
    if (bindingType === BIND_LEXICAL) {
      var scope = this.currentScope();
      redeclared = scope.lexical.indexOf(name) > -1 || scope.functions.indexOf(name) > -1 || scope.var.indexOf(name) > -1;
      scope.lexical.push(name);
      if (this.inModule && scope.flags & SCOPE_TOP) {
        delete this.undefinedExports[name];
      }
    } else if (bindingType === BIND_SIMPLE_CATCH) {
      var scope$1 = this.currentScope();
      scope$1.lexical.push(name);
    } else if (bindingType === BIND_FUNCTION) {
      var scope$2 = this.currentScope();
      if (this.treatFunctionsAsVar) {
        redeclared = scope$2.lexical.indexOf(name) > -1;
      } else {
        redeclared = scope$2.lexical.indexOf(name) > -1 || scope$2.var.indexOf(name) > -1;
      }
      scope$2.functions.push(name);
    } else {
      for (var i = this.scopeStack.length - 1; i >= 0; --i) {
        var scope$3 = this.scopeStack[i];
        if (scope$3.lexical.indexOf(name) > -1 && !(scope$3.flags & SCOPE_SIMPLE_CATCH && scope$3.lexical[0] === name) || !this.treatFunctionsAsVarInScope(scope$3) && scope$3.functions.indexOf(name) > -1) {
          redeclared = true;
          break;
        }
        scope$3.var.push(name);
        if (this.inModule && scope$3.flags & SCOPE_TOP) {
          delete this.undefinedExports[name];
        }
        if (scope$3.flags & SCOPE_VAR) {
          break;
        }
      }
    }
    if (redeclared) {
      this.raiseRecoverable(pos, "Identifier '" + name + "' has already been declared");
    }
  };
  pp$3.checkLocalExport = function(id) {
    if (this.scopeStack[0].lexical.indexOf(id.name) === -1 && this.scopeStack[0].var.indexOf(id.name) === -1) {
      this.undefinedExports[id.name] = id;
    }
  };
  pp$3.currentScope = function() {
    return this.scopeStack[this.scopeStack.length - 1];
  };
  pp$3.currentVarScope = function() {
    for (var i = this.scopeStack.length - 1; ; i--) {
      var scope = this.scopeStack[i];
      if (scope.flags & (SCOPE_VAR | SCOPE_CLASS_FIELD_INIT | SCOPE_CLASS_STATIC_BLOCK)) {
        return scope;
      }
    }
  };
  pp$3.currentThisScope = function() {
    for (var i = this.scopeStack.length - 1; ; i--) {
      var scope = this.scopeStack[i];
      if (scope.flags & (SCOPE_VAR | SCOPE_CLASS_FIELD_INIT | SCOPE_CLASS_STATIC_BLOCK) && !(scope.flags & SCOPE_ARROW)) {
        return scope;
      }
    }
  };
  var Node = /* @__PURE__ */ __name(function Node2(parser, pos, loc) {
    this.type = "";
    this.start = pos;
    this.end = 0;
    if (parser.options.locations) {
      this.loc = new SourceLocation(parser, loc);
    }
    if (parser.options.directSourceFile) {
      this.sourceFile = parser.options.directSourceFile;
    }
    if (parser.options.ranges) {
      this.range = [pos, 0];
    }
  }, "Node");
  var pp$2 = Parser.prototype;
  pp$2.startNode = function() {
    return new Node(this, this.start, this.startLoc);
  };
  pp$2.startNodeAt = function(pos, loc) {
    return new Node(this, pos, loc);
  };
  function finishNodeAt(node, type, pos, loc) {
    node.type = type;
    node.end = pos;
    if (this.options.locations) {
      node.loc.end = loc;
    }
    if (this.options.ranges) {
      node.range[1] = pos;
    }
    return node;
  }
  __name(finishNodeAt, "finishNodeAt");
  pp$2.finishNode = function(node, type) {
    return finishNodeAt.call(this, node, type, this.lastTokEnd, this.lastTokEndLoc);
  };
  pp$2.finishNodeAt = function(node, type, pos, loc) {
    return finishNodeAt.call(this, node, type, pos, loc);
  };
  pp$2.copyNode = function(node) {
    var newNode = new Node(this, node.start, this.startLoc);
    for (var prop2 in node) {
      newNode[prop2] = node[prop2];
    }
    return newNode;
  };
  var scriptValuesAddedInUnicode = "Gara Garay Gukh Gurung_Khema Hrkt Katakana_Or_Hiragana Kawi Kirat_Rai Krai Nag_Mundari Nagm Ol_Onal Onao Sunu Sunuwar Todhri Todr Tulu_Tigalari Tutg Unknown Zzzz";
  var ecma9BinaryProperties = "ASCII ASCII_Hex_Digit AHex Alphabetic Alpha Any Assigned Bidi_Control Bidi_C Bidi_Mirrored Bidi_M Case_Ignorable CI Cased Changes_When_Casefolded CWCF Changes_When_Casemapped CWCM Changes_When_Lowercased CWL Changes_When_NFKC_Casefolded CWKCF Changes_When_Titlecased CWT Changes_When_Uppercased CWU Dash Default_Ignorable_Code_Point DI Deprecated Dep Diacritic Dia Emoji Emoji_Component Emoji_Modifier Emoji_Modifier_Base Emoji_Presentation Extender Ext Grapheme_Base Gr_Base Grapheme_Extend Gr_Ext Hex_Digit Hex IDS_Binary_Operator IDSB IDS_Trinary_Operator IDST ID_Continue IDC ID_Start IDS Ideographic Ideo Join_Control Join_C Logical_Order_Exception LOE Lowercase Lower Math Noncharacter_Code_Point NChar Pattern_Syntax Pat_Syn Pattern_White_Space Pat_WS Quotation_Mark QMark Radical Regional_Indicator RI Sentence_Terminal STerm Soft_Dotted SD Terminal_Punctuation Term Unified_Ideograph UIdeo Uppercase Upper Variation_Selector VS White_Space space XID_Continue XIDC XID_Start XIDS";
  var ecma10BinaryProperties = ecma9BinaryProperties + " Extended_Pictographic";
  var ecma11BinaryProperties = ecma10BinaryProperties;
  var ecma12BinaryProperties = ecma11BinaryProperties + " EBase EComp EMod EPres ExtPict";
  var ecma13BinaryProperties = ecma12BinaryProperties;
  var ecma14BinaryProperties = ecma13BinaryProperties;
  var unicodeBinaryProperties = {
    9: ecma9BinaryProperties,
    10: ecma10BinaryProperties,
    11: ecma11BinaryProperties,
    12: ecma12BinaryProperties,
    13: ecma13BinaryProperties,
    14: ecma14BinaryProperties
  };
  var ecma14BinaryPropertiesOfStrings = "Basic_Emoji Emoji_Keycap_Sequence RGI_Emoji_Modifier_Sequence RGI_Emoji_Flag_Sequence RGI_Emoji_Tag_Sequence RGI_Emoji_ZWJ_Sequence RGI_Emoji";
  var unicodeBinaryPropertiesOfStrings = {
    9: "",
    10: "",
    11: "",
    12: "",
    13: "",
    14: ecma14BinaryPropertiesOfStrings
  };
  var unicodeGeneralCategoryValues = "Cased_Letter LC Close_Punctuation Pe Connector_Punctuation Pc Control Cc cntrl Currency_Symbol Sc Dash_Punctuation Pd Decimal_Number Nd digit Enclosing_Mark Me Final_Punctuation Pf Format Cf Initial_Punctuation Pi Letter L Letter_Number Nl Line_Separator Zl Lowercase_Letter Ll Mark M Combining_Mark Math_Symbol Sm Modifier_Letter Lm Modifier_Symbol Sk Nonspacing_Mark Mn Number N Open_Punctuation Ps Other C Other_Letter Lo Other_Number No Other_Punctuation Po Other_Symbol So Paragraph_Separator Zp Private_Use Co Punctuation P punct Separator Z Space_Separator Zs Spacing_Mark Mc Surrogate Cs Symbol S Titlecase_Letter Lt Unassigned Cn Uppercase_Letter Lu";
  var ecma9ScriptValues = "Adlam Adlm Ahom Anatolian_Hieroglyphs Hluw Arabic Arab Armenian Armn Avestan Avst Balinese Bali Bamum Bamu Bassa_Vah Bass Batak Batk Bengali Beng Bhaiksuki Bhks Bopomofo Bopo Brahmi Brah Braille Brai Buginese Bugi Buhid Buhd Canadian_Aboriginal Cans Carian Cari Caucasian_Albanian Aghb Chakma Cakm Cham Cham Cherokee Cher Common Zyyy Coptic Copt Qaac Cuneiform Xsux Cypriot Cprt Cyrillic Cyrl Deseret Dsrt Devanagari Deva Duployan Dupl Egyptian_Hieroglyphs Egyp Elbasan Elba Ethiopic Ethi Georgian Geor Glagolitic Glag Gothic Goth Grantha Gran Greek Grek Gujarati Gujr Gurmukhi Guru Han Hani Hangul Hang Hanunoo Hano Hatran Hatr Hebrew Hebr Hiragana Hira Imperial_Aramaic Armi Inherited Zinh Qaai Inscriptional_Pahlavi Phli Inscriptional_Parthian Prti Javanese Java Kaithi Kthi Kannada Knda Katakana Kana Kayah_Li Kali Kharoshthi Khar Khmer Khmr Khojki Khoj Khudawadi Sind Lao Laoo Latin Latn Lepcha Lepc Limbu Limb Linear_A Lina Linear_B Linb Lisu Lisu Lycian Lyci Lydian Lydi Mahajani Mahj Malayalam Mlym Mandaic Mand Manichaean Mani Marchen Marc Masaram_Gondi Gonm Meetei_Mayek Mtei Mende_Kikakui Mend Meroitic_Cursive Merc Meroitic_Hieroglyphs Mero Miao Plrd Modi Mongolian Mong Mro Mroo Multani Mult Myanmar Mymr Nabataean Nbat New_Tai_Lue Talu Newa Newa Nko Nkoo Nushu Nshu Ogham Ogam Ol_Chiki Olck Old_Hungarian Hung Old_Italic Ital Old_North_Arabian Narb Old_Permic Perm Old_Persian Xpeo Old_South_Arabian Sarb Old_Turkic Orkh Oriya Orya Osage Osge Osmanya Osma Pahawh_Hmong Hmng Palmyrene Palm Pau_Cin_Hau Pauc Phags_Pa Phag Phoenician Phnx Psalter_Pahlavi Phlp Rejang Rjng Runic Runr Samaritan Samr Saurashtra Saur Sharada Shrd Shavian Shaw Siddham Sidd SignWriting Sgnw Sinhala Sinh Sora_Sompeng Sora Soyombo Soyo Sundanese Sund Syloti_Nagri Sylo Syriac Syrc Tagalog Tglg Tagbanwa Tagb Tai_Le Tale Tai_Tham Lana Tai_Viet Tavt Takri Takr Tamil Taml Tangut Tang Telugu Telu Thaana Thaa Thai Thai Tibetan Tibt Tifinagh Tfng Tirhuta Tirh Ugaritic Ugar Vai Vaii Warang_Citi Wara Yi Yiii Zanabazar_Square Zanb";
  var ecma10ScriptValues = ecma9ScriptValues + " Dogra Dogr Gunjala_Gondi Gong Hanifi_Rohingya Rohg Makasar Maka Medefaidrin Medf Old_Sogdian Sogo Sogdian Sogd";
  var ecma11ScriptValues = ecma10ScriptValues + " Elymaic Elym Nandinagari Nand Nyiakeng_Puachue_Hmong Hmnp Wancho Wcho";
  var ecma12ScriptValues = ecma11ScriptValues + " Chorasmian Chrs Diak Dives_Akuru Khitan_Small_Script Kits Yezi Yezidi";
  var ecma13ScriptValues = ecma12ScriptValues + " Cypro_Minoan Cpmn Old_Uyghur Ougr Tangsa Tnsa Toto Vithkuqi Vith";
  var ecma14ScriptValues = ecma13ScriptValues + " " + scriptValuesAddedInUnicode;
  var unicodeScriptValues = {
    9: ecma9ScriptValues,
    10: ecma10ScriptValues,
    11: ecma11ScriptValues,
    12: ecma12ScriptValues,
    13: ecma13ScriptValues,
    14: ecma14ScriptValues
  };
  var data = {};
  function buildUnicodeData(ecmaVersion) {
    var d = data[ecmaVersion] = {
      binary: wordsRegexp(unicodeBinaryProperties[ecmaVersion] + " " + unicodeGeneralCategoryValues),
      binaryOfStrings: wordsRegexp(unicodeBinaryPropertiesOfStrings[ecmaVersion]),
      nonBinary: {
        General_Category: wordsRegexp(unicodeGeneralCategoryValues),
        Script: wordsRegexp(unicodeScriptValues[ecmaVersion])
      }
    };
    d.nonBinary.Script_Extensions = d.nonBinary.Script;
    d.nonBinary.gc = d.nonBinary.General_Category;
    d.nonBinary.sc = d.nonBinary.Script;
    d.nonBinary.scx = d.nonBinary.Script_Extensions;
  }
  __name(buildUnicodeData, "buildUnicodeData");
  for (i = 0, list = [9, 10, 11, 12, 13, 14]; i < list.length; i += 1) {
    ecmaVersion = list[i];
    buildUnicodeData(ecmaVersion);
  }
  var ecmaVersion;
  var i;
  var list;
  var pp$1 = Parser.prototype;
  var BranchID = /* @__PURE__ */ __name(function BranchID2(parent, base) {
    this.parent = parent;
    this.base = base || this;
  }, "BranchID");
  BranchID.prototype.separatedFrom = /* @__PURE__ */ __name(function separatedFrom(alt) {
    for (var self = this; self; self = self.parent) {
      for (var other = alt; other; other = other.parent) {
        if (self.base === other.base && self !== other) {
          return true;
        }
      }
    }
    return false;
  }, "separatedFrom");
  BranchID.prototype.sibling = /* @__PURE__ */ __name(function sibling() {
    return new BranchID(this.parent, this.base);
  }, "sibling");
  var RegExpValidationState = /* @__PURE__ */ __name(function RegExpValidationState2(parser) {
    this.parser = parser;
    this.validFlags = "gim" + (parser.options.ecmaVersion >= 6 ? "uy" : "") + (parser.options.ecmaVersion >= 9 ? "s" : "") + (parser.options.ecmaVersion >= 13 ? "d" : "") + (parser.options.ecmaVersion >= 15 ? "v" : "");
    this.unicodeProperties = data[parser.options.ecmaVersion >= 14 ? 14 : parser.options.ecmaVersion];
    this.source = "";
    this.flags = "";
    this.start = 0;
    this.switchU = false;
    this.switchV = false;
    this.switchN = false;
    this.pos = 0;
    this.lastIntValue = 0;
    this.lastStringValue = "";
    this.lastAssertionIsQuantifiable = false;
    this.numCapturingParens = 0;
    this.maxBackReference = 0;
    this.groupNames = /* @__PURE__ */ Object.create(null);
    this.backReferenceNames = [];
    this.branchID = null;
  }, "RegExpValidationState");
  RegExpValidationState.prototype.reset = /* @__PURE__ */ __name(function reset(start2, pattern, flags) {
    var unicodeSets = flags.indexOf("v") !== -1;
    var unicode = flags.indexOf("u") !== -1;
    this.start = start2 | 0;
    this.source = pattern + "";
    this.flags = flags;
    if (unicodeSets && this.parser.options.ecmaVersion >= 15) {
      this.switchU = true;
      this.switchV = true;
      this.switchN = true;
    } else {
      this.switchU = unicode && this.parser.options.ecmaVersion >= 6;
      this.switchV = false;
      this.switchN = unicode && this.parser.options.ecmaVersion >= 9;
    }
  }, "reset");
  RegExpValidationState.prototype.raise = /* @__PURE__ */ __name(function raise(message) {
    this.parser.raiseRecoverable(this.start, "Invalid regular expression: /" + this.source + "/: " + message);
  }, "raise");
  RegExpValidationState.prototype.at = /* @__PURE__ */ __name(function at(i, forceU) {
    if (forceU === void 0) forceU = false;
    var s = this.source;
    var l = s.length;
    if (i >= l) {
      return -1;
    }
    var c = s.charCodeAt(i);
    if (!(forceU || this.switchU) || c <= 55295 || c >= 57344 || i + 1 >= l) {
      return c;
    }
    var next = s.charCodeAt(i + 1);
    return next >= 56320 && next <= 57343 ? (c << 10) + next - 56613888 : c;
  }, "at");
  RegExpValidationState.prototype.nextIndex = /* @__PURE__ */ __name(function nextIndex(i, forceU) {
    if (forceU === void 0) forceU = false;
    var s = this.source;
    var l = s.length;
    if (i >= l) {
      return l;
    }
    var c = s.charCodeAt(i), next;
    if (!(forceU || this.switchU) || c <= 55295 || c >= 57344 || i + 1 >= l || (next = s.charCodeAt(i + 1)) < 56320 || next > 57343) {
      return i + 1;
    }
    return i + 2;
  }, "nextIndex");
  RegExpValidationState.prototype.current = /* @__PURE__ */ __name(function current(forceU) {
    if (forceU === void 0) forceU = false;
    return this.at(this.pos, forceU);
  }, "current");
  RegExpValidationState.prototype.lookahead = /* @__PURE__ */ __name(function lookahead(forceU) {
    if (forceU === void 0) forceU = false;
    return this.at(this.nextIndex(this.pos, forceU), forceU);
  }, "lookahead");
  RegExpValidationState.prototype.advance = /* @__PURE__ */ __name(function advance(forceU) {
    if (forceU === void 0) forceU = false;
    this.pos = this.nextIndex(this.pos, forceU);
  }, "advance");
  RegExpValidationState.prototype.eat = /* @__PURE__ */ __name(function eat(ch, forceU) {
    if (forceU === void 0) forceU = false;
    if (this.current(forceU) === ch) {
      this.advance(forceU);
      return true;
    }
    return false;
  }, "eat");
  RegExpValidationState.prototype.eatChars = /* @__PURE__ */ __name(function eatChars(chs, forceU) {
    if (forceU === void 0) forceU = false;
    var pos = this.pos;
    for (var i = 0, list = chs; i < list.length; i += 1) {
      var ch = list[i];
      var current2 = this.at(pos, forceU);
      if (current2 === -1 || current2 !== ch) {
        return false;
      }
      pos = this.nextIndex(pos, forceU);
    }
    this.pos = pos;
    return true;
  }, "eatChars");
  pp$1.validateRegExpFlags = function(state) {
    var validFlags = state.validFlags;
    var flags = state.flags;
    var u = false;
    var v = false;
    for (var i = 0; i < flags.length; i++) {
      var flag = flags.charAt(i);
      if (validFlags.indexOf(flag) === -1) {
        this.raise(state.start, "Invalid regular expression flag");
      }
      if (flags.indexOf(flag, i + 1) > -1) {
        this.raise(state.start, "Duplicate regular expression flag");
      }
      if (flag === "u") {
        u = true;
      }
      if (flag === "v") {
        v = true;
      }
    }
    if (this.options.ecmaVersion >= 15 && u && v) {
      this.raise(state.start, "Invalid regular expression flag");
    }
  };
  function hasProp(obj) {
    for (var _ in obj) {
      return true;
    }
    return false;
  }
  __name(hasProp, "hasProp");
  pp$1.validateRegExpPattern = function(state) {
    this.regexp_pattern(state);
    if (!state.switchN && this.options.ecmaVersion >= 9 && hasProp(state.groupNames)) {
      state.switchN = true;
      this.regexp_pattern(state);
    }
  };
  pp$1.regexp_pattern = function(state) {
    state.pos = 0;
    state.lastIntValue = 0;
    state.lastStringValue = "";
    state.lastAssertionIsQuantifiable = false;
    state.numCapturingParens = 0;
    state.maxBackReference = 0;
    state.groupNames = /* @__PURE__ */ Object.create(null);
    state.backReferenceNames.length = 0;
    state.branchID = null;
    this.regexp_disjunction(state);
    if (state.pos !== state.source.length) {
      if (state.eat(
        41
        /* ) */
      )) {
        state.raise("Unmatched ')'");
      }
      if (state.eat(
        93
        /* ] */
      ) || state.eat(
        125
        /* } */
      )) {
        state.raise("Lone quantifier brackets");
      }
    }
    if (state.maxBackReference > state.numCapturingParens) {
      state.raise("Invalid escape");
    }
    for (var i = 0, list = state.backReferenceNames; i < list.length; i += 1) {
      var name = list[i];
      if (!state.groupNames[name]) {
        state.raise("Invalid named capture referenced");
      }
    }
  };
  pp$1.regexp_disjunction = function(state) {
    var trackDisjunction = this.options.ecmaVersion >= 16;
    if (trackDisjunction) {
      state.branchID = new BranchID(state.branchID, null);
    }
    this.regexp_alternative(state);
    while (state.eat(
      124
      /* | */
    )) {
      if (trackDisjunction) {
        state.branchID = state.branchID.sibling();
      }
      this.regexp_alternative(state);
    }
    if (trackDisjunction) {
      state.branchID = state.branchID.parent;
    }
    if (this.regexp_eatQuantifier(state, true)) {
      state.raise("Nothing to repeat");
    }
    if (state.eat(
      123
      /* { */
    )) {
      state.raise("Lone quantifier brackets");
    }
  };
  pp$1.regexp_alternative = function(state) {
    while (state.pos < state.source.length && this.regexp_eatTerm(state)) {
    }
  };
  pp$1.regexp_eatTerm = function(state) {
    if (this.regexp_eatAssertion(state)) {
      if (state.lastAssertionIsQuantifiable && this.regexp_eatQuantifier(state)) {
        if (state.switchU) {
          state.raise("Invalid quantifier");
        }
      }
      return true;
    }
    if (state.switchU ? this.regexp_eatAtom(state) : this.regexp_eatExtendedAtom(state)) {
      this.regexp_eatQuantifier(state);
      return true;
    }
    return false;
  };
  pp$1.regexp_eatAssertion = function(state) {
    var start2 = state.pos;
    state.lastAssertionIsQuantifiable = false;
    if (state.eat(
      94
      /* ^ */
    ) || state.eat(
      36
      /* $ */
    )) {
      return true;
    }
    if (state.eat(
      92
      /* \ */
    )) {
      if (state.eat(
        66
        /* B */
      ) || state.eat(
        98
        /* b */
      )) {
        return true;
      }
      state.pos = start2;
    }
    if (state.eat(
      40
      /* ( */
    ) && state.eat(
      63
      /* ? */
    )) {
      var lookbehind = false;
      if (this.options.ecmaVersion >= 9) {
        lookbehind = state.eat(
          60
          /* < */
        );
      }
      if (state.eat(
        61
        /* = */
      ) || state.eat(
        33
        /* ! */
      )) {
        this.regexp_disjunction(state);
        if (!state.eat(
          41
          /* ) */
        )) {
          state.raise("Unterminated group");
        }
        state.lastAssertionIsQuantifiable = !lookbehind;
        return true;
      }
    }
    state.pos = start2;
    return false;
  };
  pp$1.regexp_eatQuantifier = function(state, noError) {
    if (noError === void 0) noError = false;
    if (this.regexp_eatQuantifierPrefix(state, noError)) {
      state.eat(
        63
        /* ? */
      );
      return true;
    }
    return false;
  };
  pp$1.regexp_eatQuantifierPrefix = function(state, noError) {
    return state.eat(
      42
      /* * */
    ) || state.eat(
      43
      /* + */
    ) || state.eat(
      63
      /* ? */
    ) || this.regexp_eatBracedQuantifier(state, noError);
  };
  pp$1.regexp_eatBracedQuantifier = function(state, noError) {
    var start2 = state.pos;
    if (state.eat(
      123
      /* { */
    )) {
      var min = 0, max = -1;
      if (this.regexp_eatDecimalDigits(state)) {
        min = state.lastIntValue;
        if (state.eat(
          44
          /* , */
        ) && this.regexp_eatDecimalDigits(state)) {
          max = state.lastIntValue;
        }
        if (state.eat(
          125
          /* } */
        )) {
          if (max !== -1 && max < min && !noError) {
            state.raise("numbers out of order in {} quantifier");
          }
          return true;
        }
      }
      if (state.switchU && !noError) {
        state.raise("Incomplete quantifier");
      }
      state.pos = start2;
    }
    return false;
  };
  pp$1.regexp_eatAtom = function(state) {
    return this.regexp_eatPatternCharacters(state) || state.eat(
      46
      /* . */
    ) || this.regexp_eatReverseSolidusAtomEscape(state) || this.regexp_eatCharacterClass(state) || this.regexp_eatUncapturingGroup(state) || this.regexp_eatCapturingGroup(state);
  };
  pp$1.regexp_eatReverseSolidusAtomEscape = function(state) {
    var start2 = state.pos;
    if (state.eat(
      92
      /* \ */
    )) {
      if (this.regexp_eatAtomEscape(state)) {
        return true;
      }
      state.pos = start2;
    }
    return false;
  };
  pp$1.regexp_eatUncapturingGroup = function(state) {
    var start2 = state.pos;
    if (state.eat(
      40
      /* ( */
    )) {
      if (state.eat(
        63
        /* ? */
      )) {
        if (this.options.ecmaVersion >= 16) {
          var addModifiers = this.regexp_eatModifiers(state);
          var hasHyphen = state.eat(
            45
            /* - */
          );
          if (addModifiers || hasHyphen) {
            for (var i = 0; i < addModifiers.length; i++) {
              var modifier = addModifiers.charAt(i);
              if (addModifiers.indexOf(modifier, i + 1) > -1) {
                state.raise("Duplicate regular expression modifiers");
              }
            }
            if (hasHyphen) {
              var removeModifiers = this.regexp_eatModifiers(state);
              if (!addModifiers && !removeModifiers && state.current() === 58) {
                state.raise("Invalid regular expression modifiers");
              }
              for (var i$1 = 0; i$1 < removeModifiers.length; i$1++) {
                var modifier$1 = removeModifiers.charAt(i$1);
                if (removeModifiers.indexOf(modifier$1, i$1 + 1) > -1 || addModifiers.indexOf(modifier$1) > -1) {
                  state.raise("Duplicate regular expression modifiers");
                }
              }
            }
          }
        }
        if (state.eat(
          58
          /* : */
        )) {
          this.regexp_disjunction(state);
          if (state.eat(
            41
            /* ) */
          )) {
            return true;
          }
          state.raise("Unterminated group");
        }
      }
      state.pos = start2;
    }
    return false;
  };
  pp$1.regexp_eatCapturingGroup = function(state) {
    if (state.eat(
      40
      /* ( */
    )) {
      if (this.options.ecmaVersion >= 9) {
        this.regexp_groupSpecifier(state);
      } else if (state.current() === 63) {
        state.raise("Invalid group");
      }
      this.regexp_disjunction(state);
      if (state.eat(
        41
        /* ) */
      )) {
        state.numCapturingParens += 1;
        return true;
      }
      state.raise("Unterminated group");
    }
    return false;
  };
  pp$1.regexp_eatModifiers = function(state) {
    var modifiers = "";
    var ch = 0;
    while ((ch = state.current()) !== -1 && isRegularExpressionModifier(ch)) {
      modifiers += codePointToString(ch);
      state.advance();
    }
    return modifiers;
  };
  function isRegularExpressionModifier(ch) {
    return ch === 105 || ch === 109 || ch === 115;
  }
  __name(isRegularExpressionModifier, "isRegularExpressionModifier");
  pp$1.regexp_eatExtendedAtom = function(state) {
    return state.eat(
      46
      /* . */
    ) || this.regexp_eatReverseSolidusAtomEscape(state) || this.regexp_eatCharacterClass(state) || this.regexp_eatUncapturingGroup(state) || this.regexp_eatCapturingGroup(state) || this.regexp_eatInvalidBracedQuantifier(state) || this.regexp_eatExtendedPatternCharacter(state);
  };
  pp$1.regexp_eatInvalidBracedQuantifier = function(state) {
    if (this.regexp_eatBracedQuantifier(state, true)) {
      state.raise("Nothing to repeat");
    }
    return false;
  };
  pp$1.regexp_eatSyntaxCharacter = function(state) {
    var ch = state.current();
    if (isSyntaxCharacter(ch)) {
      state.lastIntValue = ch;
      state.advance();
      return true;
    }
    return false;
  };
  function isSyntaxCharacter(ch) {
    return ch === 36 || ch >= 40 && ch <= 43 || ch === 46 || ch === 63 || ch >= 91 && ch <= 94 || ch >= 123 && ch <= 125;
  }
  __name(isSyntaxCharacter, "isSyntaxCharacter");
  pp$1.regexp_eatPatternCharacters = function(state) {
    var start2 = state.pos;
    var ch = 0;
    while ((ch = state.current()) !== -1 && !isSyntaxCharacter(ch)) {
      state.advance();
    }
    return state.pos !== start2;
  };
  pp$1.regexp_eatExtendedPatternCharacter = function(state) {
    var ch = state.current();
    if (ch !== -1 && ch !== 36 && !(ch >= 40 && ch <= 43) && ch !== 46 && ch !== 63 && ch !== 91 && ch !== 94 && ch !== 124) {
      state.advance();
      return true;
    }
    return false;
  };
  pp$1.regexp_groupSpecifier = function(state) {
    if (state.eat(
      63
      /* ? */
    )) {
      if (!this.regexp_eatGroupName(state)) {
        state.raise("Invalid group");
      }
      var trackDisjunction = this.options.ecmaVersion >= 16;
      var known = state.groupNames[state.lastStringValue];
      if (known) {
        if (trackDisjunction) {
          for (var i = 0, list = known; i < list.length; i += 1) {
            var altID = list[i];
            if (!altID.separatedFrom(state.branchID)) {
              state.raise("Duplicate capture group name");
            }
          }
        } else {
          state.raise("Duplicate capture group name");
        }
      }
      if (trackDisjunction) {
        (known || (state.groupNames[state.lastStringValue] = [])).push(state.branchID);
      } else {
        state.groupNames[state.lastStringValue] = true;
      }
    }
  };
  pp$1.regexp_eatGroupName = function(state) {
    state.lastStringValue = "";
    if (state.eat(
      60
      /* < */
    )) {
      if (this.regexp_eatRegExpIdentifierName(state) && state.eat(
        62
        /* > */
      )) {
        return true;
      }
      state.raise("Invalid capture group name");
    }
    return false;
  };
  pp$1.regexp_eatRegExpIdentifierName = function(state) {
    state.lastStringValue = "";
    if (this.regexp_eatRegExpIdentifierStart(state)) {
      state.lastStringValue += codePointToString(state.lastIntValue);
      while (this.regexp_eatRegExpIdentifierPart(state)) {
        state.lastStringValue += codePointToString(state.lastIntValue);
      }
      return true;
    }
    return false;
  };
  pp$1.regexp_eatRegExpIdentifierStart = function(state) {
    var start2 = state.pos;
    var forceU = this.options.ecmaVersion >= 11;
    var ch = state.current(forceU);
    state.advance(forceU);
    if (ch === 92 && this.regexp_eatRegExpUnicodeEscapeSequence(state, forceU)) {
      ch = state.lastIntValue;
    }
    if (isRegExpIdentifierStart(ch)) {
      state.lastIntValue = ch;
      return true;
    }
    state.pos = start2;
    return false;
  };
  function isRegExpIdentifierStart(ch) {
    return isIdentifierStart(ch, true) || ch === 36 || ch === 95;
  }
  __name(isRegExpIdentifierStart, "isRegExpIdentifierStart");
  pp$1.regexp_eatRegExpIdentifierPart = function(state) {
    var start2 = state.pos;
    var forceU = this.options.ecmaVersion >= 11;
    var ch = state.current(forceU);
    state.advance(forceU);
    if (ch === 92 && this.regexp_eatRegExpUnicodeEscapeSequence(state, forceU)) {
      ch = state.lastIntValue;
    }
    if (isRegExpIdentifierPart(ch)) {
      state.lastIntValue = ch;
      return true;
    }
    state.pos = start2;
    return false;
  };
  function isRegExpIdentifierPart(ch) {
    return isIdentifierChar(ch, true) || ch === 36 || ch === 95 || ch === 8204 || ch === 8205;
  }
  __name(isRegExpIdentifierPart, "isRegExpIdentifierPart");
  pp$1.regexp_eatAtomEscape = function(state) {
    if (this.regexp_eatBackReference(state) || this.regexp_eatCharacterClassEscape(state) || this.regexp_eatCharacterEscape(state) || state.switchN && this.regexp_eatKGroupName(state)) {
      return true;
    }
    if (state.switchU) {
      if (state.current() === 99) {
        state.raise("Invalid unicode escape");
      }
      state.raise("Invalid escape");
    }
    return false;
  };
  pp$1.regexp_eatBackReference = function(state) {
    var start2 = state.pos;
    if (this.regexp_eatDecimalEscape(state)) {
      var n = state.lastIntValue;
      if (state.switchU) {
        if (n > state.maxBackReference) {
          state.maxBackReference = n;
        }
        return true;
      }
      if (n <= state.numCapturingParens) {
        return true;
      }
      state.pos = start2;
    }
    return false;
  };
  pp$1.regexp_eatKGroupName = function(state) {
    if (state.eat(
      107
      /* k */
    )) {
      if (this.regexp_eatGroupName(state)) {
        state.backReferenceNames.push(state.lastStringValue);
        return true;
      }
      state.raise("Invalid named reference");
    }
    return false;
  };
  pp$1.regexp_eatCharacterEscape = function(state) {
    return this.regexp_eatControlEscape(state) || this.regexp_eatCControlLetter(state) || this.regexp_eatZero(state) || this.regexp_eatHexEscapeSequence(state) || this.regexp_eatRegExpUnicodeEscapeSequence(state, false) || !state.switchU && this.regexp_eatLegacyOctalEscapeSequence(state) || this.regexp_eatIdentityEscape(state);
  };
  pp$1.regexp_eatCControlLetter = function(state) {
    var start2 = state.pos;
    if (state.eat(
      99
      /* c */
    )) {
      if (this.regexp_eatControlLetter(state)) {
        return true;
      }
      state.pos = start2;
    }
    return false;
  };
  pp$1.regexp_eatZero = function(state) {
    if (state.current() === 48 && !isDecimalDigit(state.lookahead())) {
      state.lastIntValue = 0;
      state.advance();
      return true;
    }
    return false;
  };
  pp$1.regexp_eatControlEscape = function(state) {
    var ch = state.current();
    if (ch === 116) {
      state.lastIntValue = 9;
      state.advance();
      return true;
    }
    if (ch === 110) {
      state.lastIntValue = 10;
      state.advance();
      return true;
    }
    if (ch === 118) {
      state.lastIntValue = 11;
      state.advance();
      return true;
    }
    if (ch === 102) {
      state.lastIntValue = 12;
      state.advance();
      return true;
    }
    if (ch === 114) {
      state.lastIntValue = 13;
      state.advance();
      return true;
    }
    return false;
  };
  pp$1.regexp_eatControlLetter = function(state) {
    var ch = state.current();
    if (isControlLetter(ch)) {
      state.lastIntValue = ch % 32;
      state.advance();
      return true;
    }
    return false;
  };
  function isControlLetter(ch) {
    return ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122;
  }
  __name(isControlLetter, "isControlLetter");
  pp$1.regexp_eatRegExpUnicodeEscapeSequence = function(state, forceU) {
    if (forceU === void 0) forceU = false;
    var start2 = state.pos;
    var switchU = forceU || state.switchU;
    if (state.eat(
      117
      /* u */
    )) {
      if (this.regexp_eatFixedHexDigits(state, 4)) {
        var lead = state.lastIntValue;
        if (switchU && lead >= 55296 && lead <= 56319) {
          var leadSurrogateEnd = state.pos;
          if (state.eat(
            92
            /* \ */
          ) && state.eat(
            117
            /* u */
          ) && this.regexp_eatFixedHexDigits(state, 4)) {
            var trail = state.lastIntValue;
            if (trail >= 56320 && trail <= 57343) {
              state.lastIntValue = (lead - 55296) * 1024 + (trail - 56320) + 65536;
              return true;
            }
          }
          state.pos = leadSurrogateEnd;
          state.lastIntValue = lead;
        }
        return true;
      }
      if (switchU && state.eat(
        123
        /* { */
      ) && this.regexp_eatHexDigits(state) && state.eat(
        125
        /* } */
      ) && isValidUnicode(state.lastIntValue)) {
        return true;
      }
      if (switchU) {
        state.raise("Invalid unicode escape");
      }
      state.pos = start2;
    }
    return false;
  };
  function isValidUnicode(ch) {
    return ch >= 0 && ch <= 1114111;
  }
  __name(isValidUnicode, "isValidUnicode");
  pp$1.regexp_eatIdentityEscape = function(state) {
    if (state.switchU) {
      if (this.regexp_eatSyntaxCharacter(state)) {
        return true;
      }
      if (state.eat(
        47
        /* / */
      )) {
        state.lastIntValue = 47;
        return true;
      }
      return false;
    }
    var ch = state.current();
    if (ch !== 99 && (!state.switchN || ch !== 107)) {
      state.lastIntValue = ch;
      state.advance();
      return true;
    }
    return false;
  };
  pp$1.regexp_eatDecimalEscape = function(state) {
    state.lastIntValue = 0;
    var ch = state.current();
    if (ch >= 49 && ch <= 57) {
      do {
        state.lastIntValue = 10 * state.lastIntValue + (ch - 48);
        state.advance();
      } while ((ch = state.current()) >= 48 && ch <= 57);
      return true;
    }
    return false;
  };
  var CharSetNone = 0;
  var CharSetOk = 1;
  var CharSetString = 2;
  pp$1.regexp_eatCharacterClassEscape = function(state) {
    var ch = state.current();
    if (isCharacterClassEscape(ch)) {
      state.lastIntValue = -1;
      state.advance();
      return CharSetOk;
    }
    var negate = false;
    if (state.switchU && this.options.ecmaVersion >= 9 && ((negate = ch === 80) || ch === 112)) {
      state.lastIntValue = -1;
      state.advance();
      var result;
      if (state.eat(
        123
        /* { */
      ) && (result = this.regexp_eatUnicodePropertyValueExpression(state)) && state.eat(
        125
        /* } */
      )) {
        if (negate && result === CharSetString) {
          state.raise("Invalid property name");
        }
        return result;
      }
      state.raise("Invalid property name");
    }
    return CharSetNone;
  };
  function isCharacterClassEscape(ch) {
    return ch === 100 || ch === 68 || ch === 115 || ch === 83 || ch === 119 || ch === 87;
  }
  __name(isCharacterClassEscape, "isCharacterClassEscape");
  pp$1.regexp_eatUnicodePropertyValueExpression = function(state) {
    var start2 = state.pos;
    if (this.regexp_eatUnicodePropertyName(state) && state.eat(
      61
      /* = */
    )) {
      var name = state.lastStringValue;
      if (this.regexp_eatUnicodePropertyValue(state)) {
        var value = state.lastStringValue;
        this.regexp_validateUnicodePropertyNameAndValue(state, name, value);
        return CharSetOk;
      }
    }
    state.pos = start2;
    if (this.regexp_eatLoneUnicodePropertyNameOrValue(state)) {
      var nameOrValue = state.lastStringValue;
      return this.regexp_validateUnicodePropertyNameOrValue(state, nameOrValue);
    }
    return CharSetNone;
  };
  pp$1.regexp_validateUnicodePropertyNameAndValue = function(state, name, value) {
    if (!hasOwn(state.unicodeProperties.nonBinary, name)) {
      state.raise("Invalid property name");
    }
    if (!state.unicodeProperties.nonBinary[name].test(value)) {
      state.raise("Invalid property value");
    }
  };
  pp$1.regexp_validateUnicodePropertyNameOrValue = function(state, nameOrValue) {
    if (state.unicodeProperties.binary.test(nameOrValue)) {
      return CharSetOk;
    }
    if (state.switchV && state.unicodeProperties.binaryOfStrings.test(nameOrValue)) {
      return CharSetString;
    }
    state.raise("Invalid property name");
  };
  pp$1.regexp_eatUnicodePropertyName = function(state) {
    var ch = 0;
    state.lastStringValue = "";
    while (isUnicodePropertyNameCharacter(ch = state.current())) {
      state.lastStringValue += codePointToString(ch);
      state.advance();
    }
    return state.lastStringValue !== "";
  };
  function isUnicodePropertyNameCharacter(ch) {
    return isControlLetter(ch) || ch === 95;
  }
  __name(isUnicodePropertyNameCharacter, "isUnicodePropertyNameCharacter");
  pp$1.regexp_eatUnicodePropertyValue = function(state) {
    var ch = 0;
    state.lastStringValue = "";
    while (isUnicodePropertyValueCharacter(ch = state.current())) {
      state.lastStringValue += codePointToString(ch);
      state.advance();
    }
    return state.lastStringValue !== "";
  };
  function isUnicodePropertyValueCharacter(ch) {
    return isUnicodePropertyNameCharacter(ch) || isDecimalDigit(ch);
  }
  __name(isUnicodePropertyValueCharacter, "isUnicodePropertyValueCharacter");
  pp$1.regexp_eatLoneUnicodePropertyNameOrValue = function(state) {
    return this.regexp_eatUnicodePropertyValue(state);
  };
  pp$1.regexp_eatCharacterClass = function(state) {
    if (state.eat(
      91
      /* [ */
    )) {
      var negate = state.eat(
        94
        /* ^ */
      );
      var result = this.regexp_classContents(state);
      if (!state.eat(
        93
        /* ] */
      )) {
        state.raise("Unterminated character class");
      }
      if (negate && result === CharSetString) {
        state.raise("Negated character class may contain strings");
      }
      return true;
    }
    return false;
  };
  pp$1.regexp_classContents = function(state) {
    if (state.current() === 93) {
      return CharSetOk;
    }
    if (state.switchV) {
      return this.regexp_classSetExpression(state);
    }
    this.regexp_nonEmptyClassRanges(state);
    return CharSetOk;
  };
  pp$1.regexp_nonEmptyClassRanges = function(state) {
    while (this.regexp_eatClassAtom(state)) {
      var left = state.lastIntValue;
      if (state.eat(
        45
        /* - */
      ) && this.regexp_eatClassAtom(state)) {
        var right = state.lastIntValue;
        if (state.switchU && (left === -1 || right === -1)) {
          state.raise("Invalid character class");
        }
        if (left !== -1 && right !== -1 && left > right) {
          state.raise("Range out of order in character class");
        }
      }
    }
  };
  pp$1.regexp_eatClassAtom = function(state) {
    var start2 = state.pos;
    if (state.eat(
      92
      /* \ */
    )) {
      if (this.regexp_eatClassEscape(state)) {
        return true;
      }
      if (state.switchU) {
        var ch$1 = state.current();
        if (ch$1 === 99 || isOctalDigit(ch$1)) {
          state.raise("Invalid class escape");
        }
        state.raise("Invalid escape");
      }
      state.pos = start2;
    }
    var ch = state.current();
    if (ch !== 93) {
      state.lastIntValue = ch;
      state.advance();
      return true;
    }
    return false;
  };
  pp$1.regexp_eatClassEscape = function(state) {
    var start2 = state.pos;
    if (state.eat(
      98
      /* b */
    )) {
      state.lastIntValue = 8;
      return true;
    }
    if (state.switchU && state.eat(
      45
      /* - */
    )) {
      state.lastIntValue = 45;
      return true;
    }
    if (!state.switchU && state.eat(
      99
      /* c */
    )) {
      if (this.regexp_eatClassControlLetter(state)) {
        return true;
      }
      state.pos = start2;
    }
    return this.regexp_eatCharacterClassEscape(state) || this.regexp_eatCharacterEscape(state);
  };
  pp$1.regexp_classSetExpression = function(state) {
    var result = CharSetOk, subResult;
    if (this.regexp_eatClassSetRange(state)) ;
    else if (subResult = this.regexp_eatClassSetOperand(state)) {
      if (subResult === CharSetString) {
        result = CharSetString;
      }
      var start2 = state.pos;
      while (state.eatChars(
        [38, 38]
        /* && */
      )) {
        if (state.current() !== 38 && (subResult = this.regexp_eatClassSetOperand(state))) {
          if (subResult !== CharSetString) {
            result = CharSetOk;
          }
          continue;
        }
        state.raise("Invalid character in character class");
      }
      if (start2 !== state.pos) {
        return result;
      }
      while (state.eatChars(
        [45, 45]
        /* -- */
      )) {
        if (this.regexp_eatClassSetOperand(state)) {
          continue;
        }
        state.raise("Invalid character in character class");
      }
      if (start2 !== state.pos) {
        return result;
      }
    } else {
      state.raise("Invalid character in character class");
    }
    for (; ; ) {
      if (this.regexp_eatClassSetRange(state)) {
        continue;
      }
      subResult = this.regexp_eatClassSetOperand(state);
      if (!subResult) {
        return result;
      }
      if (subResult === CharSetString) {
        result = CharSetString;
      }
    }
  };
  pp$1.regexp_eatClassSetRange = function(state) {
    var start2 = state.pos;
    if (this.regexp_eatClassSetCharacter(state)) {
      var left = state.lastIntValue;
      if (state.eat(
        45
        /* - */
      ) && this.regexp_eatClassSetCharacter(state)) {
        var right = state.lastIntValue;
        if (left !== -1 && right !== -1 && left > right) {
          state.raise("Range out of order in character class");
        }
        return true;
      }
      state.pos = start2;
    }
    return false;
  };
  pp$1.regexp_eatClassSetOperand = function(state) {
    if (this.regexp_eatClassSetCharacter(state)) {
      return CharSetOk;
    }
    return this.regexp_eatClassStringDisjunction(state) || this.regexp_eatNestedClass(state);
  };
  pp$1.regexp_eatNestedClass = function(state) {
    var start2 = state.pos;
    if (state.eat(
      91
      /* [ */
    )) {
      var negate = state.eat(
        94
        /* ^ */
      );
      var result = this.regexp_classContents(state);
      if (state.eat(
        93
        /* ] */
      )) {
        if (negate && result === CharSetString) {
          state.raise("Negated character class may contain strings");
        }
        return result;
      }
      state.pos = start2;
    }
    if (state.eat(
      92
      /* \ */
    )) {
      var result$1 = this.regexp_eatCharacterClassEscape(state);
      if (result$1) {
        return result$1;
      }
      state.pos = start2;
    }
    return null;
  };
  pp$1.regexp_eatClassStringDisjunction = function(state) {
    var start2 = state.pos;
    if (state.eatChars(
      [92, 113]
      /* \q */
    )) {
      if (state.eat(
        123
        /* { */
      )) {
        var result = this.regexp_classStringDisjunctionContents(state);
        if (state.eat(
          125
          /* } */
        )) {
          return result;
        }
      } else {
        state.raise("Invalid escape");
      }
      state.pos = start2;
    }
    return null;
  };
  pp$1.regexp_classStringDisjunctionContents = function(state) {
    var result = this.regexp_classString(state);
    while (state.eat(
      124
      /* | */
    )) {
      if (this.regexp_classString(state) === CharSetString) {
        result = CharSetString;
      }
    }
    return result;
  };
  pp$1.regexp_classString = function(state) {
    var count = 0;
    while (this.regexp_eatClassSetCharacter(state)) {
      count++;
    }
    return count === 1 ? CharSetOk : CharSetString;
  };
  pp$1.regexp_eatClassSetCharacter = function(state) {
    var start2 = state.pos;
    if (state.eat(
      92
      /* \ */
    )) {
      if (this.regexp_eatCharacterEscape(state) || this.regexp_eatClassSetReservedPunctuator(state)) {
        return true;
      }
      if (state.eat(
        98
        /* b */
      )) {
        state.lastIntValue = 8;
        return true;
      }
      state.pos = start2;
      return false;
    }
    var ch = state.current();
    if (ch < 0 || ch === state.lookahead() && isClassSetReservedDoublePunctuatorCharacter(ch)) {
      return false;
    }
    if (isClassSetSyntaxCharacter(ch)) {
      return false;
    }
    state.advance();
    state.lastIntValue = ch;
    return true;
  };
  function isClassSetReservedDoublePunctuatorCharacter(ch) {
    return ch === 33 || ch >= 35 && ch <= 38 || ch >= 42 && ch <= 44 || ch === 46 || ch >= 58 && ch <= 64 || ch === 94 || ch === 96 || ch === 126;
  }
  __name(isClassSetReservedDoublePunctuatorCharacter, "isClassSetReservedDoublePunctuatorCharacter");
  function isClassSetSyntaxCharacter(ch) {
    return ch === 40 || ch === 41 || ch === 45 || ch === 47 || ch >= 91 && ch <= 93 || ch >= 123 && ch <= 125;
  }
  __name(isClassSetSyntaxCharacter, "isClassSetSyntaxCharacter");
  pp$1.regexp_eatClassSetReservedPunctuator = function(state) {
    var ch = state.current();
    if (isClassSetReservedPunctuator(ch)) {
      state.lastIntValue = ch;
      state.advance();
      return true;
    }
    return false;
  };
  function isClassSetReservedPunctuator(ch) {
    return ch === 33 || ch === 35 || ch === 37 || ch === 38 || ch === 44 || ch === 45 || ch >= 58 && ch <= 62 || ch === 64 || ch === 96 || ch === 126;
  }
  __name(isClassSetReservedPunctuator, "isClassSetReservedPunctuator");
  pp$1.regexp_eatClassControlLetter = function(state) {
    var ch = state.current();
    if (isDecimalDigit(ch) || ch === 95) {
      state.lastIntValue = ch % 32;
      state.advance();
      return true;
    }
    return false;
  };
  pp$1.regexp_eatHexEscapeSequence = function(state) {
    var start2 = state.pos;
    if (state.eat(
      120
      /* x */
    )) {
      if (this.regexp_eatFixedHexDigits(state, 2)) {
        return true;
      }
      if (state.switchU) {
        state.raise("Invalid escape");
      }
      state.pos = start2;
    }
    return false;
  };
  pp$1.regexp_eatDecimalDigits = function(state) {
    var start2 = state.pos;
    var ch = 0;
    state.lastIntValue = 0;
    while (isDecimalDigit(ch = state.current())) {
      state.lastIntValue = 10 * state.lastIntValue + (ch - 48);
      state.advance();
    }
    return state.pos !== start2;
  };
  function isDecimalDigit(ch) {
    return ch >= 48 && ch <= 57;
  }
  __name(isDecimalDigit, "isDecimalDigit");
  pp$1.regexp_eatHexDigits = function(state) {
    var start2 = state.pos;
    var ch = 0;
    state.lastIntValue = 0;
    while (isHexDigit(ch = state.current())) {
      state.lastIntValue = 16 * state.lastIntValue + hexToInt(ch);
      state.advance();
    }
    return state.pos !== start2;
  };
  function isHexDigit(ch) {
    return ch >= 48 && ch <= 57 || ch >= 65 && ch <= 70 || ch >= 97 && ch <= 102;
  }
  __name(isHexDigit, "isHexDigit");
  function hexToInt(ch) {
    if (ch >= 65 && ch <= 70) {
      return 10 + (ch - 65);
    }
    if (ch >= 97 && ch <= 102) {
      return 10 + (ch - 97);
    }
    return ch - 48;
  }
  __name(hexToInt, "hexToInt");
  pp$1.regexp_eatLegacyOctalEscapeSequence = function(state) {
    if (this.regexp_eatOctalDigit(state)) {
      var n1 = state.lastIntValue;
      if (this.regexp_eatOctalDigit(state)) {
        var n2 = state.lastIntValue;
        if (n1 <= 3 && this.regexp_eatOctalDigit(state)) {
          state.lastIntValue = n1 * 64 + n2 * 8 + state.lastIntValue;
        } else {
          state.lastIntValue = n1 * 8 + n2;
        }
      } else {
        state.lastIntValue = n1;
      }
      return true;
    }
    return false;
  };
  pp$1.regexp_eatOctalDigit = function(state) {
    var ch = state.current();
    if (isOctalDigit(ch)) {
      state.lastIntValue = ch - 48;
      state.advance();
      return true;
    }
    state.lastIntValue = 0;
    return false;
  };
  function isOctalDigit(ch) {
    return ch >= 48 && ch <= 55;
  }
  __name(isOctalDigit, "isOctalDigit");
  pp$1.regexp_eatFixedHexDigits = function(state, length) {
    var start2 = state.pos;
    state.lastIntValue = 0;
    for (var i = 0; i < length; ++i) {
      var ch = state.current();
      if (!isHexDigit(ch)) {
        state.pos = start2;
        return false;
      }
      state.lastIntValue = 16 * state.lastIntValue + hexToInt(ch);
      state.advance();
    }
    return true;
  };
  var Token = /* @__PURE__ */ __name(function Token2(p) {
    this.type = p.type;
    this.value = p.value;
    this.start = p.start;
    this.end = p.end;
    if (p.options.locations) {
      this.loc = new SourceLocation(p, p.startLoc, p.endLoc);
    }
    if (p.options.ranges) {
      this.range = [p.start, p.end];
    }
  }, "Token");
  var pp = Parser.prototype;
  pp.next = function(ignoreEscapeSequenceInKeyword) {
    if (!ignoreEscapeSequenceInKeyword && this.type.keyword && this.containsEsc) {
      this.raiseRecoverable(this.start, "Escape sequence in keyword " + this.type.keyword);
    }
    if (this.options.onToken) {
      this.options.onToken(new Token(this));
    }
    this.lastTokEnd = this.end;
    this.lastTokStart = this.start;
    this.lastTokEndLoc = this.endLoc;
    this.lastTokStartLoc = this.startLoc;
    this.nextToken();
  };
  pp.getToken = function() {
    this.next();
    return new Token(this);
  };
  if (typeof Symbol !== "undefined") {
    pp[Symbol.iterator] = function() {
      var this$1$1 = this;
      return {
        next: /* @__PURE__ */ __name(function() {
          var token = this$1$1.getToken();
          return {
            done: token.type === types$1.eof,
            value: token
          };
        }, "next")
      };
    };
  }
  pp.nextToken = function() {
    var curContext = this.curContext();
    if (!curContext || !curContext.preserveSpace) {
      this.skipSpace();
    }
    this.start = this.pos;
    if (this.options.locations) {
      this.startLoc = this.curPosition();
    }
    if (this.pos >= this.input.length) {
      return this.finishToken(types$1.eof);
    }
    if (curContext.override) {
      return curContext.override(this);
    } else {
      this.readToken(this.fullCharCodeAtPos());
    }
  };
  pp.readToken = function(code) {
    if (isIdentifierStart(code, this.options.ecmaVersion >= 6) || code === 92) {
      return this.readWord();
    }
    return this.getTokenFromCode(code);
  };
  pp.fullCharCodeAtPos = function() {
    var code = this.input.charCodeAt(this.pos);
    if (code <= 55295 || code >= 56320) {
      return code;
    }
    var next = this.input.charCodeAt(this.pos + 1);
    return next <= 56319 || next >= 57344 ? code : (code << 10) + next - 56613888;
  };
  pp.skipBlockComment = function() {
    var startLoc = this.options.onComment && this.curPosition();
    var start2 = this.pos, end = this.input.indexOf("*/", this.pos += 2);
    if (end === -1) {
      this.raise(this.pos - 2, "Unterminated comment");
    }
    this.pos = end + 2;
    if (this.options.locations) {
      for (var nextBreak = void 0, pos = start2; (nextBreak = nextLineBreak(this.input, pos, this.pos)) > -1; ) {
        ++this.curLine;
        pos = this.lineStart = nextBreak;
      }
    }
    if (this.options.onComment) {
      this.options.onComment(
        true,
        this.input.slice(start2 + 2, end),
        start2,
        this.pos,
        startLoc,
        this.curPosition()
      );
    }
  };
  pp.skipLineComment = function(startSkip) {
    var start2 = this.pos;
    var startLoc = this.options.onComment && this.curPosition();
    var ch = this.input.charCodeAt(this.pos += startSkip);
    while (this.pos < this.input.length && !isNewLine(ch)) {
      ch = this.input.charCodeAt(++this.pos);
    }
    if (this.options.onComment) {
      this.options.onComment(
        false,
        this.input.slice(start2 + startSkip, this.pos),
        start2,
        this.pos,
        startLoc,
        this.curPosition()
      );
    }
  };
  pp.skipSpace = function() {
    loop: while (this.pos < this.input.length) {
      var ch = this.input.charCodeAt(this.pos);
      switch (ch) {
        case 32:
        case 160:
          ++this.pos;
          break;
        case 13:
          if (this.input.charCodeAt(this.pos + 1) === 10) {
            ++this.pos;
          }
        case 10:
        case 8232:
        case 8233:
          ++this.pos;
          if (this.options.locations) {
            ++this.curLine;
            this.lineStart = this.pos;
          }
          break;
        case 47:
          switch (this.input.charCodeAt(this.pos + 1)) {
            case 42:
              this.skipBlockComment();
              break;
            case 47:
              this.skipLineComment(2);
              break;
            default:
              break loop;
          }
          break;
        default:
          if (ch > 8 && ch < 14 || ch >= 5760 && nonASCIIwhitespace.test(String.fromCharCode(ch))) {
            ++this.pos;
          } else {
            break loop;
          }
      }
    }
  };
  pp.finishToken = function(type, val) {
    this.end = this.pos;
    if (this.options.locations) {
      this.endLoc = this.curPosition();
    }
    var prevType = this.type;
    this.type = type;
    this.value = val;
    this.updateContext(prevType);
  };
  pp.readToken_dot = function() {
    var next = this.input.charCodeAt(this.pos + 1);
    if (next >= 48 && next <= 57) {
      return this.readNumber(true);
    }
    var next2 = this.input.charCodeAt(this.pos + 2);
    if (this.options.ecmaVersion >= 6 && next === 46 && next2 === 46) {
      this.pos += 3;
      return this.finishToken(types$1.ellipsis);
    } else {
      ++this.pos;
      return this.finishToken(types$1.dot);
    }
  };
  pp.readToken_slash = function() {
    var next = this.input.charCodeAt(this.pos + 1);
    if (this.exprAllowed) {
      ++this.pos;
      return this.readRegexp();
    }
    if (next === 61) {
      return this.finishOp(types$1.assign, 2);
    }
    return this.finishOp(types$1.slash, 1);
  };
  pp.readToken_mult_modulo_exp = function(code) {
    var next = this.input.charCodeAt(this.pos + 1);
    var size = 1;
    var tokentype = code === 42 ? types$1.star : types$1.modulo;
    if (this.options.ecmaVersion >= 7 && code === 42 && next === 42) {
      ++size;
      tokentype = types$1.starstar;
      next = this.input.charCodeAt(this.pos + 2);
    }
    if (next === 61) {
      return this.finishOp(types$1.assign, size + 1);
    }
    return this.finishOp(tokentype, size);
  };
  pp.readToken_pipe_amp = function(code) {
    var next = this.input.charCodeAt(this.pos + 1);
    if (next === code) {
      if (this.options.ecmaVersion >= 12) {
        var next2 = this.input.charCodeAt(this.pos + 2);
        if (next2 === 61) {
          return this.finishOp(types$1.assign, 3);
        }
      }
      return this.finishOp(code === 124 ? types$1.logicalOR : types$1.logicalAND, 2);
    }
    if (next === 61) {
      return this.finishOp(types$1.assign, 2);
    }
    return this.finishOp(code === 124 ? types$1.bitwiseOR : types$1.bitwiseAND, 1);
  };
  pp.readToken_caret = function() {
    var next = this.input.charCodeAt(this.pos + 1);
    if (next === 61) {
      return this.finishOp(types$1.assign, 2);
    }
    return this.finishOp(types$1.bitwiseXOR, 1);
  };
  pp.readToken_plus_min = function(code) {
    var next = this.input.charCodeAt(this.pos + 1);
    if (next === code) {
      if (next === 45 && !this.inModule && this.input.charCodeAt(this.pos + 2) === 62 && (this.lastTokEnd === 0 || lineBreak.test(this.input.slice(this.lastTokEnd, this.pos)))) {
        this.skipLineComment(3);
        this.skipSpace();
        return this.nextToken();
      }
      return this.finishOp(types$1.incDec, 2);
    }
    if (next === 61) {
      return this.finishOp(types$1.assign, 2);
    }
    return this.finishOp(types$1.plusMin, 1);
  };
  pp.readToken_lt_gt = function(code) {
    var next = this.input.charCodeAt(this.pos + 1);
    var size = 1;
    if (next === code) {
      size = code === 62 && this.input.charCodeAt(this.pos + 2) === 62 ? 3 : 2;
      if (this.input.charCodeAt(this.pos + size) === 61) {
        return this.finishOp(types$1.assign, size + 1);
      }
      return this.finishOp(types$1.bitShift, size);
    }
    if (next === 33 && code === 60 && !this.inModule && this.input.charCodeAt(this.pos + 2) === 45 && this.input.charCodeAt(this.pos + 3) === 45) {
      this.skipLineComment(4);
      this.skipSpace();
      return this.nextToken();
    }
    if (next === 61) {
      size = 2;
    }
    return this.finishOp(types$1.relational, size);
  };
  pp.readToken_eq_excl = function(code) {
    var next = this.input.charCodeAt(this.pos + 1);
    if (next === 61) {
      return this.finishOp(types$1.equality, this.input.charCodeAt(this.pos + 2) === 61 ? 3 : 2);
    }
    if (code === 61 && next === 62 && this.options.ecmaVersion >= 6) {
      this.pos += 2;
      return this.finishToken(types$1.arrow);
    }
    return this.finishOp(code === 61 ? types$1.eq : types$1.prefix, 1);
  };
  pp.readToken_question = function() {
    var ecmaVersion = this.options.ecmaVersion;
    if (ecmaVersion >= 11) {
      var next = this.input.charCodeAt(this.pos + 1);
      if (next === 46) {
        var next2 = this.input.charCodeAt(this.pos + 2);
        if (next2 < 48 || next2 > 57) {
          return this.finishOp(types$1.questionDot, 2);
        }
      }
      if (next === 63) {
        if (ecmaVersion >= 12) {
          var next2$1 = this.input.charCodeAt(this.pos + 2);
          if (next2$1 === 61) {
            return this.finishOp(types$1.assign, 3);
          }
        }
        return this.finishOp(types$1.coalesce, 2);
      }
    }
    return this.finishOp(types$1.question, 1);
  };
  pp.readToken_numberSign = function() {
    var ecmaVersion = this.options.ecmaVersion;
    var code = 35;
    if (ecmaVersion >= 13) {
      ++this.pos;
      code = this.fullCharCodeAtPos();
      if (isIdentifierStart(code, true) || code === 92) {
        return this.finishToken(types$1.privateId, this.readWord1());
      }
    }
    this.raise(this.pos, "Unexpected character '" + codePointToString(code) + "'");
  };
  pp.getTokenFromCode = function(code) {
    switch (code) {
      // The interpretation of a dot depends on whether it is followed
      // by a digit or another two dots.
      case 46:
        return this.readToken_dot();
      // Punctuation tokens.
      case 40:
        ++this.pos;
        return this.finishToken(types$1.parenL);
      case 41:
        ++this.pos;
        return this.finishToken(types$1.parenR);
      case 59:
        ++this.pos;
        return this.finishToken(types$1.semi);
      case 44:
        ++this.pos;
        return this.finishToken(types$1.comma);
      case 91:
        ++this.pos;
        return this.finishToken(types$1.bracketL);
      case 93:
        ++this.pos;
        return this.finishToken(types$1.bracketR);
      case 123:
        ++this.pos;
        return this.finishToken(types$1.braceL);
      case 125:
        ++this.pos;
        return this.finishToken(types$1.braceR);
      case 58:
        ++this.pos;
        return this.finishToken(types$1.colon);
      case 96:
        if (this.options.ecmaVersion < 6) {
          break;
        }
        ++this.pos;
        return this.finishToken(types$1.backQuote);
      case 48:
        var next = this.input.charCodeAt(this.pos + 1);
        if (next === 120 || next === 88) {
          return this.readRadixNumber(16);
        }
        if (this.options.ecmaVersion >= 6) {
          if (next === 111 || next === 79) {
            return this.readRadixNumber(8);
          }
          if (next === 98 || next === 66) {
            return this.readRadixNumber(2);
          }
        }
      // Anything else beginning with a digit is an integer, octal
      // number, or float.
      case 49:
      case 50:
      case 51:
      case 52:
      case 53:
      case 54:
      case 55:
      case 56:
      case 57:
        return this.readNumber(false);
      // Quotes produce strings.
      case 34:
      case 39:
        return this.readString(code);
      // Operators are parsed inline in tiny state machines. '=' (61) is
      // often referred to. `finishOp` simply skips the amount of
      // characters it is given as second argument, and returns a token
      // of the type given by its first argument.
      case 47:
        return this.readToken_slash();
      case 37:
      case 42:
        return this.readToken_mult_modulo_exp(code);
      case 124:
      case 38:
        return this.readToken_pipe_amp(code);
      case 94:
        return this.readToken_caret();
      case 43:
      case 45:
        return this.readToken_plus_min(code);
      case 60:
      case 62:
        return this.readToken_lt_gt(code);
      case 61:
      case 33:
        return this.readToken_eq_excl(code);
      case 63:
        return this.readToken_question();
      case 126:
        return this.finishOp(types$1.prefix, 1);
      case 35:
        return this.readToken_numberSign();
    }
    this.raise(this.pos, "Unexpected character '" + codePointToString(code) + "'");
  };
  pp.finishOp = function(type, size) {
    var str = this.input.slice(this.pos, this.pos + size);
    this.pos += size;
    return this.finishToken(type, str);
  };
  pp.readRegexp = function() {
    var escaped, inClass, start2 = this.pos;
    for (; ; ) {
      if (this.pos >= this.input.length) {
        this.raise(start2, "Unterminated regular expression");
      }
      var ch = this.input.charAt(this.pos);
      if (lineBreak.test(ch)) {
        this.raise(start2, "Unterminated regular expression");
      }
      if (!escaped) {
        if (ch === "[") {
          inClass = true;
        } else if (ch === "]" && inClass) {
          inClass = false;
        } else if (ch === "/" && !inClass) {
          break;
        }
        escaped = ch === "\\";
      } else {
        escaped = false;
      }
      ++this.pos;
    }
    var pattern = this.input.slice(start2, this.pos);
    ++this.pos;
    var flagsStart = this.pos;
    var flags = this.readWord1();
    if (this.containsEsc) {
      this.unexpected(flagsStart);
    }
    var state = this.regexpState || (this.regexpState = new RegExpValidationState(this));
    state.reset(start2, pattern, flags);
    this.validateRegExpFlags(state);
    this.validateRegExpPattern(state);
    var value = null;
    try {
      value = new RegExp(pattern, flags);
    } catch (e) {
    }
    return this.finishToken(types$1.regexp, { pattern, flags, value });
  };
  pp.readInt = function(radix, len, maybeLegacyOctalNumericLiteral) {
    var allowSeparators = this.options.ecmaVersion >= 12 && len === void 0;
    var isLegacyOctalNumericLiteral = maybeLegacyOctalNumericLiteral && this.input.charCodeAt(this.pos) === 48;
    var start2 = this.pos, total = 0, lastCode = 0;
    for (var i = 0, e = len == null ? Infinity : len; i < e; ++i, ++this.pos) {
      var code = this.input.charCodeAt(this.pos), val = void 0;
      if (allowSeparators && code === 95) {
        if (isLegacyOctalNumericLiteral) {
          this.raiseRecoverable(this.pos, "Numeric separator is not allowed in legacy octal numeric literals");
        }
        if (lastCode === 95) {
          this.raiseRecoverable(this.pos, "Numeric separator must be exactly one underscore");
        }
        if (i === 0) {
          this.raiseRecoverable(this.pos, "Numeric separator is not allowed at the first of digits");
        }
        lastCode = code;
        continue;
      }
      if (code >= 97) {
        val = code - 97 + 10;
      } else if (code >= 65) {
        val = code - 65 + 10;
      } else if (code >= 48 && code <= 57) {
        val = code - 48;
      } else {
        val = Infinity;
      }
      if (val >= radix) {
        break;
      }
      lastCode = code;
      total = total * radix + val;
    }
    if (allowSeparators && lastCode === 95) {
      this.raiseRecoverable(this.pos - 1, "Numeric separator is not allowed at the last of digits");
    }
    if (this.pos === start2 || len != null && this.pos - start2 !== len) {
      return null;
    }
    return total;
  };
  function stringToNumber(str, isLegacyOctalNumericLiteral) {
    if (isLegacyOctalNumericLiteral) {
      return parseInt(str, 8);
    }
    return parseFloat(str.replace(/_/g, ""));
  }
  __name(stringToNumber, "stringToNumber");
  function stringToBigInt(str) {
    if (typeof BigInt !== "function") {
      return null;
    }
    return BigInt(str.replace(/_/g, ""));
  }
  __name(stringToBigInt, "stringToBigInt");
  pp.readRadixNumber = function(radix) {
    var start2 = this.pos;
    this.pos += 2;
    var val = this.readInt(radix);
    if (val == null) {
      this.raise(this.start + 2, "Expected number in radix " + radix);
    }
    if (this.options.ecmaVersion >= 11 && this.input.charCodeAt(this.pos) === 110) {
      val = stringToBigInt(this.input.slice(start2, this.pos));
      ++this.pos;
    } else if (isIdentifierStart(this.fullCharCodeAtPos())) {
      this.raise(this.pos, "Identifier directly after number");
    }
    return this.finishToken(types$1.num, val);
  };
  pp.readNumber = function(startsWithDot) {
    var start2 = this.pos;
    if (!startsWithDot && this.readInt(10, void 0, true) === null) {
      this.raise(start2, "Invalid number");
    }
    var octal = this.pos - start2 >= 2 && this.input.charCodeAt(start2) === 48;
    if (octal && this.strict) {
      this.raise(start2, "Invalid number");
    }
    var next = this.input.charCodeAt(this.pos);
    if (!octal && !startsWithDot && this.options.ecmaVersion >= 11 && next === 110) {
      var val$1 = stringToBigInt(this.input.slice(start2, this.pos));
      ++this.pos;
      if (isIdentifierStart(this.fullCharCodeAtPos())) {
        this.raise(this.pos, "Identifier directly after number");
      }
      return this.finishToken(types$1.num, val$1);
    }
    if (octal && /[89]/.test(this.input.slice(start2, this.pos))) {
      octal = false;
    }
    if (next === 46 && !octal) {
      ++this.pos;
      this.readInt(10);
      next = this.input.charCodeAt(this.pos);
    }
    if ((next === 69 || next === 101) && !octal) {
      next = this.input.charCodeAt(++this.pos);
      if (next === 43 || next === 45) {
        ++this.pos;
      }
      if (this.readInt(10) === null) {
        this.raise(start2, "Invalid number");
      }
    }
    if (isIdentifierStart(this.fullCharCodeAtPos())) {
      this.raise(this.pos, "Identifier directly after number");
    }
    var val = stringToNumber(this.input.slice(start2, this.pos), octal);
    return this.finishToken(types$1.num, val);
  };
  pp.readCodePoint = function() {
    var ch = this.input.charCodeAt(this.pos), code;
    if (ch === 123) {
      if (this.options.ecmaVersion < 6) {
        this.unexpected();
      }
      var codePos = ++this.pos;
      code = this.readHexChar(this.input.indexOf("}", this.pos) - this.pos);
      ++this.pos;
      if (code > 1114111) {
        this.invalidStringToken(codePos, "Code point out of bounds");
      }
    } else {
      code = this.readHexChar(4);
    }
    return code;
  };
  pp.readString = function(quote) {
    var out = "", chunkStart = ++this.pos;
    for (; ; ) {
      if (this.pos >= this.input.length) {
        this.raise(this.start, "Unterminated string constant");
      }
      var ch = this.input.charCodeAt(this.pos);
      if (ch === quote) {
        break;
      }
      if (ch === 92) {
        out += this.input.slice(chunkStart, this.pos);
        out += this.readEscapedChar(false);
        chunkStart = this.pos;
      } else if (ch === 8232 || ch === 8233) {
        if (this.options.ecmaVersion < 10) {
          this.raise(this.start, "Unterminated string constant");
        }
        ++this.pos;
        if (this.options.locations) {
          this.curLine++;
          this.lineStart = this.pos;
        }
      } else {
        if (isNewLine(ch)) {
          this.raise(this.start, "Unterminated string constant");
        }
        ++this.pos;
      }
    }
    out += this.input.slice(chunkStart, this.pos++);
    return this.finishToken(types$1.string, out);
  };
  var INVALID_TEMPLATE_ESCAPE_ERROR = {};
  pp.tryReadTemplateToken = function() {
    this.inTemplateElement = true;
    try {
      this.readTmplToken();
    } catch (err) {
      if (err === INVALID_TEMPLATE_ESCAPE_ERROR) {
        this.readInvalidTemplateToken();
      } else {
        throw err;
      }
    }
    this.inTemplateElement = false;
  };
  pp.invalidStringToken = function(position, message) {
    if (this.inTemplateElement && this.options.ecmaVersion >= 9) {
      throw INVALID_TEMPLATE_ESCAPE_ERROR;
    } else {
      this.raise(position, message);
    }
  };
  pp.readTmplToken = function() {
    var out = "", chunkStart = this.pos;
    for (; ; ) {
      if (this.pos >= this.input.length) {
        this.raise(this.start, "Unterminated template");
      }
      var ch = this.input.charCodeAt(this.pos);
      if (ch === 96 || ch === 36 && this.input.charCodeAt(this.pos + 1) === 123) {
        if (this.pos === this.start && (this.type === types$1.template || this.type === types$1.invalidTemplate)) {
          if (ch === 36) {
            this.pos += 2;
            return this.finishToken(types$1.dollarBraceL);
          } else {
            ++this.pos;
            return this.finishToken(types$1.backQuote);
          }
        }
        out += this.input.slice(chunkStart, this.pos);
        return this.finishToken(types$1.template, out);
      }
      if (ch === 92) {
        out += this.input.slice(chunkStart, this.pos);
        out += this.readEscapedChar(true);
        chunkStart = this.pos;
      } else if (isNewLine(ch)) {
        out += this.input.slice(chunkStart, this.pos);
        ++this.pos;
        switch (ch) {
          case 13:
            if (this.input.charCodeAt(this.pos) === 10) {
              ++this.pos;
            }
          case 10:
            out += "\n";
            break;
          default:
            out += String.fromCharCode(ch);
            break;
        }
        if (this.options.locations) {
          ++this.curLine;
          this.lineStart = this.pos;
        }
        chunkStart = this.pos;
      } else {
        ++this.pos;
      }
    }
  };
  pp.readInvalidTemplateToken = function() {
    for (; this.pos < this.input.length; this.pos++) {
      switch (this.input[this.pos]) {
        case "\\":
          ++this.pos;
          break;
        case "$":
          if (this.input[this.pos + 1] !== "{") {
            break;
          }
        // fall through
        case "`":
          return this.finishToken(types$1.invalidTemplate, this.input.slice(this.start, this.pos));
        case "\r":
          if (this.input[this.pos + 1] === "\n") {
            ++this.pos;
          }
        // fall through
        case "\n":
        case "\u2028":
        case "\u2029":
          ++this.curLine;
          this.lineStart = this.pos + 1;
          break;
      }
    }
    this.raise(this.start, "Unterminated template");
  };
  pp.readEscapedChar = function(inTemplate) {
    var ch = this.input.charCodeAt(++this.pos);
    ++this.pos;
    switch (ch) {
      case 110:
        return "\n";
      // 'n' -> '\n'
      case 114:
        return "\r";
      // 'r' -> '\r'
      case 120:
        return String.fromCharCode(this.readHexChar(2));
      // 'x'
      case 117:
        return codePointToString(this.readCodePoint());
      // 'u'
      case 116:
        return "	";
      // 't' -> '\t'
      case 98:
        return "\b";
      // 'b' -> '\b'
      case 118:
        return "\v";
      // 'v' -> '\u000b'
      case 102:
        return "\f";
      // 'f' -> '\f'
      case 13:
        if (this.input.charCodeAt(this.pos) === 10) {
          ++this.pos;
        }
      // '\r\n'
      case 10:
        if (this.options.locations) {
          this.lineStart = this.pos;
          ++this.curLine;
        }
        return "";
      case 56:
      case 57:
        if (this.strict) {
          this.invalidStringToken(
            this.pos - 1,
            "Invalid escape sequence"
          );
        }
        if (inTemplate) {
          var codePos = this.pos - 1;
          this.invalidStringToken(
            codePos,
            "Invalid escape sequence in template string"
          );
        }
      default:
        if (ch >= 48 && ch <= 55) {
          var octalStr = this.input.substr(this.pos - 1, 3).match(/^[0-7]+/)[0];
          var octal = parseInt(octalStr, 8);
          if (octal > 255) {
            octalStr = octalStr.slice(0, -1);
            octal = parseInt(octalStr, 8);
          }
          this.pos += octalStr.length - 1;
          ch = this.input.charCodeAt(this.pos);
          if ((octalStr !== "0" || ch === 56 || ch === 57) && (this.strict || inTemplate)) {
            this.invalidStringToken(
              this.pos - 1 - octalStr.length,
              inTemplate ? "Octal literal in template string" : "Octal literal in strict mode"
            );
          }
          return String.fromCharCode(octal);
        }
        if (isNewLine(ch)) {
          if (this.options.locations) {
            this.lineStart = this.pos;
            ++this.curLine;
          }
          return "";
        }
        return String.fromCharCode(ch);
    }
  };
  pp.readHexChar = function(len) {
    var codePos = this.pos;
    var n = this.readInt(16, len);
    if (n === null) {
      this.invalidStringToken(codePos, "Bad character escape sequence");
    }
    return n;
  };
  pp.readWord1 = function() {
    this.containsEsc = false;
    var word = "", first = true, chunkStart = this.pos;
    var astral = this.options.ecmaVersion >= 6;
    while (this.pos < this.input.length) {
      var ch = this.fullCharCodeAtPos();
      if (isIdentifierChar(ch, astral)) {
        this.pos += ch <= 65535 ? 1 : 2;
      } else if (ch === 92) {
        this.containsEsc = true;
        word += this.input.slice(chunkStart, this.pos);
        var escStart = this.pos;
        if (this.input.charCodeAt(++this.pos) !== 117) {
          this.invalidStringToken(this.pos, "Expecting Unicode escape sequence \\uXXXX");
        }
        ++this.pos;
        var esc = this.readCodePoint();
        if (!(first ? isIdentifierStart : isIdentifierChar)(esc, astral)) {
          this.invalidStringToken(escStart, "Invalid Unicode escape");
        }
        word += codePointToString(esc);
        chunkStart = this.pos;
      } else {
        break;
      }
      first = false;
    }
    return word + this.input.slice(chunkStart, this.pos);
  };
  pp.readWord = function() {
    var word = this.readWord1();
    var type = types$1.name;
    if (this.keywords.test(word)) {
      type = keywords[word];
    }
    return this.finishToken(type, word);
  };
  var version = "8.15.0";
  Parser.acorn = {
    Parser,
    version,
    defaultOptions,
    Position,
    SourceLocation,
    getLineInfo,
    Node,
    TokenType,
    tokTypes: types$1,
    keywordTypes: keywords,
    TokContext,
    tokContexts: types,
    isIdentifierChar,
    isIdentifierStart,
    Token,
    isNewLine,
    lineBreak,
    lineBreakG,
    nonASCIIwhitespace
  };
  function parse3(input, options) {
    return Parser.parse(input, options);
  }
  __name(parse3, "parse");

  // src/core.mjs
  var nativeSource = Function.prototype.toString;
  var object = /* @__PURE__ */ __name((v) => v !== null && typeof v === "object", "object");
  var finite = /* @__PURE__ */ __name((v) => typeof v === "number" && Number.isFinite(v), "finite");
  var vec = /* @__PURE__ */ __name((v) => object(v) && finite(read(v, "x")) && finite(read(v, "y")), "vec");
  var clamp = /* @__PURE__ */ __name((v, lo, hi) => Math.max(lo, Math.min(hi, v)), "clamp");
  var point = /* @__PURE__ */ __name((v) => ({ x: read(v, "x"), y: read(v, "y") }), "point");
  var sameLayer = /* @__PURE__ */ __name((a, b) => finite(a) && finite(b) && ((a & 1) === (b & 1) || !!(a & 2 && b & 2)), "sameLayer");
  function entries(o) {
    if (!object(o) && typeof o !== "function") return [];
    try {
      return Object.entries(Object.getOwnPropertyDescriptors(o)).filter(([, d]) => "value" in d).map(([k, d]) => [k, d.value]);
    } catch {
      return [];
    }
  }
  __name(entries, "entries");
  function read(o, k) {
    if (!object(o) && typeof o !== "function" || k === null || k === void 0) return void 0;
    try {
      const d = Object.getOwnPropertyDescriptor(o, k);
      return d && "value" in d ? d.value : void 0;
    } catch {
      return void 0;
    }
  }
  __name(read, "read");
  function at2(o, path2) {
    for (const k of path2) o = read(o, k);
    return o;
  }
  __name(at2, "at");
  function unique(xs) {
    const values = [...new Set(xs)];
    return values.length === 1 ? values[0] : null;
  }
  __name(unique, "unique");
  function methods(o) {
    const found = /* @__PURE__ */ new Map();
    try {
      for (let i = 0; o && i < 4 && o !== Object.prototype; o = Object.getPrototypeOf(o), i++) {
        for (const [k, v] of entries(o)) if (!found.has(k) && typeof v === "function" && k !== "constructor") found.set(k, v);
      }
    } catch {
    }
    return [...found];
  }
  __name(methods, "methods");
  var astCache = /* @__PURE__ */ new WeakMap();
  function ast(fn) {
    if (typeof fn !== "function") return null;
    if (astCache.has(fn)) return astCache.get(fn);
    let tree = null;
    try {
      const code = Reflect.apply(nativeSource, fn, []);
      try {
        tree = parse3(`(${code})`, { ecmaVersion: "latest" }).body[0].expression;
      } catch {
        tree = parse3(`({${code}})`, { ecmaVersion: "latest" }).body[0].expression.properties[0].value;
      }
    } catch {
    }
    astCache.set(fn, tree);
    return tree;
  }
  __name(ast, "ast");
  function walk(node, visit) {
    if (!node || typeof node !== "object") return;
    if (typeof node.type === "string") visit(node);
    for (const [k, v] of Object.entries(node)) {
      if (k === "start" || k === "end") continue;
      if (Array.isArray(v)) v.forEach((child) => walk(child, visit));
      else if (v && typeof v === "object") walk(v, visit);
    }
  }
  __name(walk, "walk");
  function prop(node) {
    return node?.type === "Identifier" ? node.name : node?.type === "Literal" && typeof node.value === "string" ? node.value : null;
  }
  __name(prop, "prop");
  function path(node, root = "this") {
    if (node?.type === "ChainExpression") return path(node.expression, root);
    if (root === "this" && node?.type === "ThisExpression") return [];
    if (node?.type === "Identifier" && node.name === root) return [];
    if (node?.type !== "MemberExpression") return null;
    const base = path(node.object, root);
    const key = node.computed ? node.property.type === "Literal" ? prop(node.property) : null : prop(node.property);
    return base && key !== null ? [...base, key] : null;
  }
  __name(path, "path");
  function paths(tree, root = "this") {
    const result = /* @__PURE__ */ new Map();
    walk(tree, (n) => {
      const p = path(n, root);
      if (p?.length) result.set(JSON.stringify(p), p);
    });
    return [...result.values()];
  }
  __name(paths, "paths");
  function memberName(node) {
    return node?.type === "MemberExpression" ? node.computed ? node.property.value : node.property.name : null;
  }
  __name(memberName, "memberName");
  function calls(tree, name) {
    const found = [];
    walk(tree, (n) => {
      if (n.type === "CallExpression" && memberName(n.callee) === name) found.push(n);
    });
    return found;
  }
  __name(calls, "calls");
  function isPlayer(p) {
    return object(p) && finite(read(p, "__id")) && typeof read(p, "active") === "boolean" && object(read(p, "container")) && object(read(p, "nameText"));
  }
  __name(isPlayer, "isPlayer");
  function isApplication(app) {
    const pixi = read(app, "pixi");
    if (!object(app) || !object(read(app, "game")) || !object(read(pixi, "stage"))) return false;
    const ticker = read(pixi, "ticker") || read(pixi, "_ticker");
    let resolved = ticker;
    try {
      resolved ||= pixi?.ticker;
    } catch {
      return false;
    }
    return object(app) && object(read(app, "game")) && object(read(pixi, "stage")) && object(resolved) && typeof resolved.add === "function" && typeof resolved.remove === "function";
  }
  __name(isApplication, "isApplication");
  function discoverSender(game) {
    return unique(methods(game).filter(([, fn]) => {
      const tree = ast(fn);
      return calls(tree, "serializeMsg").length === 1;
    }).map(([k]) => k));
  }
  __name(discoverSender, "discoverSender");
  function discoverCamera(game) {
    const candidates = [];
    for (const [gameKey, camera] of entries(game)) {
      if (!object(camera) || Array.isArray(camera) || isPlayer(camera)) continue;
      const values = entries(camera).map(([, value]) => value);
      if (!values.some(vec) || !values.some(finite)) continue;
      for (const [method, fn] of methods(camera)) {
        const tree = ast(fn), param = tree?.params?.[0]?.name;
        if (!param) continue;
        walk(tree?.body, (node) => {
          if (node.type !== "ReturnStatement" || node.argument?.type !== "ObjectExpression") return;
          const xp = node.argument.properties.find((p) => prop(p.key) === "x")?.value;
          const yp = node.argument.properties.find((p) => prop(p.key) === "y")?.value;
          if (!xp || !yp) return;
          const px = paths(xp, param), py = paths(yp, param);
          if (!px.some((p) => p.length === 1 && p[0] === "x") || !py.some((p) => p.length === 1 && p[0] === "y")) return;
          let multiplication = false, division = false;
          walk(node.argument, (n) => {
            if (n.type === "BinaryExpression" && n.operator === "*") multiplication = true;
            if (n.type === "BinaryExpression" && n.operator === "/") division = true;
          });
          if (!multiplication || division) return;
          const self = paths(node.argument);
          const posKey = unique(self.filter((p) => p.length === 2 && ["x", "y"].includes(p[1]) && vec(read(camera, p[0]))).map((p) => p[0]));
          const widthKey = unique(paths(xp).filter((p) => p.length === 1 && finite(at2(camera, p))).map((p) => p[0]));
          const heightKey = unique(paths(yp).filter((p) => p.length === 1 && finite(at2(camera, p))).map((p) => p[0]));
          const scaleCalls = [];
          walk(node.argument, (n) => {
            if (n.type === "CallExpression") {
              const p = path(n.callee);
              if (p?.length === 1 && typeof readMethod(camera, p[0]) === "function") scaleCalls.push(p[0]);
            }
          });
          const scaleMethod = unique(scaleCalls);
          if (!posKey || !widthKey || !heightKey || !scaleMethod) return;
          const isPath = /* @__PURE__ */ __name((node2, keys, root = "this") => JSON.stringify(path(node2, root)) === JSON.stringify(keys), "isPath");
          const product = /* @__PURE__ */ __name((node2, left, right) => node2?.type === "BinaryExpression" && node2.operator === "*" && (left(node2.left) && right(node2.right) || right(node2.left) && left(node2.right)), "product");
          const half = /* @__PURE__ */ __name((node2) => node2?.type === "Literal" && node2.value === 0.5, "half");
          const scaledDelta = /* @__PURE__ */ __name((node2, axis) => product(
            node2,
            (n) => n?.type === "BinaryExpression" && n.operator === "-" && isPath(n.left, [axis], param) && isPath(n.right, [posKey, axis]),
            (n) => n?.type === "CallExpression" && n.arguments.length === 0 && isPath(n.callee, [scaleMethod])
          ), "scaledDelta");
          const dimension = /* @__PURE__ */ __name((node2, key) => product(node2, (n) => isPath(n, [key]), half), "dimension");
          if (!(xp.type === "BinaryExpression" && xp.operator === "+" && dimension(xp.left, widthKey) && scaledDelta(xp.right, "x") && yp.type === "BinaryExpression" && yp.operator === "-" && dimension(yp.left, heightKey) && scaledDelta(yp.right, "y"))) return;
          const scaleTree = ast(readMethod(camera, scaleMethod));
          const scaleKeys = paths(scaleTree).filter((p) => p.length === 1 && finite(at2(camera, p))).map((p) => p[0]);
          if (new Set(scaleKeys).size !== 2) return;
          let zoomKey = null;
          if (scaleKeys.includes("m_zoom")) zoomKey = "m_zoom";
          for (const [, gameFn] of methods(game)) {
            walk(ast(gameFn), (n) => {
              if (n.type !== "AssignmentExpression" || n.right?.type !== "CallExpression") return;
              const lhs = path(n.left);
              if (lhs?.length !== 2 || lhs[0] !== gameKey || !scaleKeys.includes(lhs[1])) return;
              const rhs = paths(n.right).filter((p) => p[0] === gameKey && p.length === 2);
              if (rhs.some((p) => p[1] === lhs[1]) && rhs.some((p) => p[1] !== lhs[1] && finite(at2(game, p)))) zoomKey = lhs[1];
            });
          }
          candidates.push({ camera, gameKey, method, posKey, widthKey, heightKey, scaleMethod, scaleKeys, zoomKey });
        });
      }
    }
    return candidates.length === 1 ? candidates[0] : null;
  }
  __name(discoverCamera, "discoverCamera");
  function readMethod(o, key) {
    return methods(o).find(([k]) => k === key)?.[1];
  }
  __name(readMethod, "readMethod");
  function project(mapping, world) {
    if (!mapping || !vec(world)) return null;
    const { camera, posKey, widthKey, heightKey, scaleKeys } = mapping;
    const center = read(camera, posKey), width = read(camera, widthKey), height = read(camera, heightKey);
    const scale = read(camera, scaleKeys[0]) * read(camera, scaleKeys[1]);
    if (!vec(center) || !finite(width) || !finite(height) || width <= 0 || height <= 0 || !finite(scale) || scale <= 0) return null;
    return { x: width * 0.5 + (world.x - center.x) * scale, y: height * 0.5 - (world.y - center.y) * scale };
  }
  __name(project, "project");
  function aimPoint(camera, world, playerPos) {
    const target = project(camera, world), origin = project(camera, playerPos);
    if (!target || !origin) return null;
    return {
      x: read(camera.camera, camera.widthKey) * 0.5 + target.x - origin.x,
      y: read(camera.camera, camera.heightKey) * 0.5 + target.y - origin.y
    };
  }
  __name(aimPoint, "aimPoint");
  function discoverVisualPosition(player, projectionMethod) {
    const tree = ast(readMethod(player, "render")), root = tree?.params?.[0]?.name;
    if (!root || !projectionMethod) return null;
    const candidates = [];
    walk(tree, (n) => {
      if (n.type !== "VariableDeclarator" || n.id?.type !== "Identifier" || n.init?.type !== "CallExpression") return;
      const callee = path(n.init.callee, root), source = path(n.init.arguments[0]);
      if (callee?.length !== 1 || callee[0] !== projectionMethod || n.init.arguments.length !== 1 || source?.length !== 1 || !vec(at2(player, source))) return;
      let consumed = false;
      walk(tree, (call) => {
        if (call.type !== "CallExpression") return;
        const dest = path(call.callee);
        if (dest?.join(".") === "container.position.set" && call.arguments.length === 2 && path(call.arguments[0], n.id.name)?.join(".") === "x" && path(call.arguments[1], n.id.name)?.join(".") === "y") consumed = true;
      });
      if (consumed) candidates.push(source[0]);
    });
    return unique(candidates);
  }
  __name(discoverVisualPosition, "discoverVisualPosition");
  function overlayPosition(player, mapping) {
    const visual = read(player, mapping.visualPosKey);
    return vec(visual) ? visual : read(player, mapping.schema?.posKey);
  }
  __name(overlayPosition, "overlayPosition");
  function discoverPlayerSchema(player) {
    if (!isPlayer(player)) return null;
    const idle = ast(readMethod(player, "selectIdlePose"));
    const interact = ast(readMethod(player, "canInteract"));
    const melee = ast(readMethod(player, "getMeleeCollider"));
    const netPath = unique(paths(idle).filter((p) => p.length === 2 && typeof at2(player, p) === "string").map((p) => p.join("\0")))?.split("\0");
    const negated = [];
    walk(interact, (n) => {
      if (n.type === "UnaryExpression" && n.operator === "!") {
        const p = path(n.argument);
        if (p?.length === 2 && typeof at2(player, p) === "boolean") negated.push(p.join("\0"));
      }
    });
    const deadPath = unique(negated)?.split("\0");
    const dirs = /* @__PURE__ */ new Set();
    for (const call of calls(melee, "atan2")) for (const p of paths(call)) if (p.length === 2 && ["x", "y"].includes(p[1])) dirs.add(p[0]);
    const posKey = unique(paths(melee).filter((p) => p.length === 1 && vec(at2(player, p)) && !dirs.has(p[0])).map((p) => p[0]));
    if (!netPath || !deadPath || netPath[0] !== deadPath[0] || !posKey) return null;
    return { netKey: netPath[0], weaponKey: netPath[1], deadKey: deadPath[1], posKey, dirKey: unique([...dirs]) };
  }
  __name(discoverPlayerSchema, "discoverPlayerSchema");
  function discover(game) {
    const objects = entries(game).filter(([, v]) => object(v) && !Array.isArray(v));
    const barns = objects.filter(([, v]) => object(read(v, "teamInfo")) && Array.isArray(read(v, "playerIds")) && object(read(v, "playerPool")));
    const barn = barns.length === 1 ? barns[0][1] : null;
    const pool = read(barn, "playerPool");
    const arrays = entries(pool).filter(([, v]) => Array.isArray(v) && v.length > 0 && v.every(isPlayer));
    const poolKey = arrays.length === 1 ? arrays[0][0] : null;
    const players = /* @__PURE__ */ __name(() => {
      const current2 = read(pool, poolKey);
      return Array.isArray(current2) ? current2.filter((p) => isPlayer(p) && read(p, "active")) : [];
    }, "players");
    const active = unique(objects.filter(([, p]) => isPlayer(p) && players().includes(p)).map(([, p]) => p));
    const schema = active ? discoverPlayerSchema(active) : null;
    const ui = unique(objects.filter(([, v]) => typeof readMethod(v, "setSpectating") === "function" && typeof read(v, "spectating") === "boolean").map(([, v]) => v));
    const map = unique(objects.filter(([, v]) => entries(v).some(([k]) => k === "mapTexture") && typeof readMethod(v, "getGroundSurface") === "function").map(([, v]) => v));
    const creators = objects.filter(([, v]) => entries(v).some(([, x]) => object(x) && !Array.isArray(x) && entries(x).some(([, entity]) => finite(read(entity, "__id")) && finite(read(entity, "__type")))));
    const creator = creators.length === 1 ? creators[0][1] : null;
    const registryKey = unique(entries(creator).filter(([, x]) => object(x) && !Array.isArray(x) && entries(x).some(([, e]) => finite(read(e, "__id")) && finite(read(e, "__type")))).map(([k]) => k));
    const obstacles = /* @__PURE__ */ __name(() => entries(read(creator, registryKey)).map(([, v]) => v).filter((v) => object(read(v, "collider")) && typeof read(v, "collidable") === "boolean"), "obstacles");
    const activeKey = unique(objects.filter(([, value]) => value === active).map(([key]) => key));
    const camera = discoverCamera(game);
    const visualPosKey = active && camera ? discoverVisualPosition(active, camera.method) : null;
    return { game, barn, barnKey: barns.length === 1 ? barns[0][0] : null, pool, poolKey, players, active, activeKey, schema, ui, map, camera, visualPosKey, obstacles, creator, registryKey };
  }
  __name(discover, "discover");
  function discoverLootSource(game) {
    const found = [];
    for (const [, owner] of entries(game)) {
      const tree = ast(readMethod(owner, "getClosestLoot"));
      const body = tree?.body?.body;
      if (body?.length !== 1 || body[0].type !== "ReturnStatement") continue;
      const p = path(body[0].argument);
      if (p?.length === 1 && (read(owner, p[0]) === null || object(read(owner, p[0])))) found.push({ owner, key: p[0] });
    }
    return found.length === 1 ? found[0] : null;
  }
  __name(discoverLootSource, "discoverLootSource");
  function membershipIndex(table) {
    const index = /* @__PURE__ */ new Map();
    let budget = 8192;
    const records = entries(table);
    if (records.length > 1024) return /* @__PURE__ */ new Map();
    for (const [key, group] of records) {
      const ids = read(group, "playerIds");
      if (!Array.isArray(ids)) continue;
      for (const id of ids) {
        if (--budget < 0) return /* @__PURE__ */ new Map();
        if (!Number.isInteger(id) || id < 0) continue;
        if (!index.has(id)) index.set(id, key);
        else if (index.get(id) !== key) index.set(id, null);
      }
    }
    return index;
  }
  __name(membershipIndex, "membershipIndex");
  function teamRelations(barn, ownId) {
    const teams = membershipIndex(read(barn, "teamInfo"));
    const groups = membershipIndex(read(barn, "groupInfo"));
    const ownTeam = teams.get(ownId), ownGroup = groups.get(ownId);
    return {
      ready: ownTeam !== void 0 && ownTeam !== null,
      classify(id) {
        if (id === ownId) return { kind: "self", squad: false };
        const team = teams.get(id), group = groups.get(id);
        if (ownTeam === void 0 || ownTeam === null || team === void 0 || team === null) return { kind: "unknown", squad: false };
        const ally = team === ownTeam;
        return { kind: ally ? "ally" : "enemy", squad: ally && ownGroup !== void 0 && ownGroup !== null && group === ownGroup };
      }
    };
  }
  __name(teamRelations, "teamRelations");
  function localWeapon(mapping) {
    const { active, schema } = mapping || {};
    return active && schema ? at2(active, [schema.netKey, schema.weaponKey]) : null;
  }
  __name(localWeapon, "localWeapon");
  function intercept(relative, velocity, speed, maxTime = 2) {
    if (!vec(relative) || !vec(velocity) || !finite(speed) || speed <= 0) return null;
    const a = velocity.x ** 2 + velocity.y ** 2 - speed ** 2;
    const b = 2 * (relative.x * velocity.x + relative.y * velocity.y);
    const c = relative.x ** 2 + relative.y ** 2;
    if (c < 1e-12) return 0;
    let roots;
    if (Math.abs(a) < 1e-8) roots = Math.abs(b) > 1e-8 ? [-c / b] : [];
    else {
      const disc = b * b - 4 * a * c;
      if (disc < 0) return null;
      const q = -0.5 * (b + (b >= 0 ? 1 : -1) * Math.sqrt(disc));
      roots = q === 0 ? [-b / (2 * a)] : [q / a, c / q];
    }
    const positive = roots.filter((t) => finite(t) && t >= 0 && t <= maxTime);
    return positive.length ? Math.min(...positive) : null;
  }
  __name(intercept, "intercept");
  var Tracker = class {
    static {
      __name(this, "Tracker");
    }
    states = /* @__PURE__ */ new WeakMap();
    reset() {
      this.states = /* @__PURE__ */ new WeakMap();
    }
    update(entity, pos, now) {
      const id = read(entity, "__id");
      let st = this.states.get(entity);
      if (!st || st.id !== id || now - st.time > 500 || now <= st.time) {
        st = { id, pos: point(pos), time: now, vx: 0, vy: 0 };
        this.states.set(entity, st);
        return st;
      }
      const dt = (now - st.time) / 1e3;
      if (dt < 8e-3) return st;
      const vx = (pos.x - st.pos.x) / dt, vy = (pos.y - st.pos.y) / dt;
      if (Math.hypot(vx, vy) > 80) {
        st.vx = st.vy = 0;
      } else {
        const len = Math.hypot(vx, vy) * Math.hypot(st.vx, st.vy);
        const turn = len > 1 && (vx * st.vx + vy * st.vy) / len < 0.35;
        const gain = turn ? 1 : 1 - Math.exp(-dt / 0.06);
        st.vx += (vx - st.vx) * gain;
        st.vy += (vy - st.vy) * gain;
      }
      st.pos = point(pos);
      st.time = now;
      return st;
    }
  };
  function segmentBlocked(start2, end, collider) {
    const dx = end.x - start2.x, dy = end.y - start2.y;
    const type = read(collider, "type");
    if (type === 0 && vec(read(collider, "pos")) && finite(read(collider, "rad"))) {
      const c = read(collider, "pos"), rad = read(collider, "rad");
      const d2 = dx * dx + dy * dy;
      const t = d2 > 0 ? clamp(((c.x - start2.x) * dx + (c.y - start2.y) * dy) / d2, 0, 1) : 0;
      return (start2.x + dx * t - c.x) ** 2 + (start2.y + dy * t - c.y) ** 2 <= rad * rad;
    }
    if (type === 1 && vec(read(collider, "min")) && vec(read(collider, "max"))) {
      let lo = 0, hi = 1;
      for (const [axis, delta] of [["x", dx], ["y", dy]]) {
        const min = collider.min[axis], max = collider.max[axis];
        if (Math.abs(delta) < 1e-10) {
          if (start2[axis] < min || start2[axis] > max) return false;
        } else {
          const t1 = (min - start2[axis]) / delta, t2 = (max - start2[axis]) / delta;
          lo = Math.max(lo, Math.min(t1, t2));
          hi = Math.min(hi, Math.max(t1, t2));
          if (lo > hi) return false;
        }
      }
      return true;
    }
    return true;
  }
  __name(segmentBlocked, "segmentBlocked");
  var Disposables = class {
    static {
      __name(this, "Disposables");
    }
    tasks = [];
    add(fn) {
      this.tasks.push(fn);
      return fn;
    }
    clear() {
      const errors = [];
      for (const fn of this.tasks.splice(0).reverse()) {
        try {
          fn();
        } catch (e) {
          errors.push(e);
        }
      }
      return errors;
    }
  };
  function patchMethod(owner, key, makeWrapper, bag) {
    const original = owner?.[key];
    if (typeof original !== "function") return false;
    const descriptor = Object.getOwnPropertyDescriptor(owner, key);
    if (descriptor && !descriptor.configurable && !descriptor.writable) return false;
    const wrapper = makeWrapper(original);
    try {
      Object.defineProperty(owner, key, { configurable: true, enumerable: descriptor?.enumerable ?? false, writable: true, value: wrapper });
    } catch {
      return false;
    }
    bag.add(() => {
      if (owner[key] !== wrapper) return;
      if (descriptor) Object.defineProperty(owner, key, descriptor);
      else delete owner[key];
    });
    return true;
  }
  __name(patchMethod, "patchMethod");
  function captureApplication(win, onApp, { timeout = 15e3, onTimeout = /* @__PURE__ */ __name(() => {
  }, "onTimeout") } = {}) {
    const bag = new Disposables(), proto = win.Function.prototype;
    const apply = win.Reflect.apply;
    let inHook = false, done = false, cancelled = false;
    const finish = /* @__PURE__ */ __name(() => {
      done = true;
      bag.clear();
    }, "finish");
    const cancel = /* @__PURE__ */ __name(() => {
      cancelled = true;
      finish();
    }, "cancel");
    const installed = patchMethod(proto, "call", (original) => function(self) {
      let captured = false;
      if (!done && !inHook) {
        inHook = true;
        try {
          captured = isApplication(self);
        } catch {
        } finally {
          inHook = false;
        }
      }
      if (captured) {
        finish();
        win.queueMicrotask(() => {
          if (!cancelled) onApp(self);
        });
      }
      return apply(original, this, arguments);
    }, bag);
    if (!installed) {
      onTimeout();
      return cancel;
    }
    const timer = win.setTimeout(() => {
      if (!done) {
        cancel();
        onTimeout();
      }
    }, timeout);
    bag.add(() => win.clearTimeout(timer));
    return cancel;
  }
  __name(captureApplication, "captureApplication");
  function captureDefinitions(win, onDefs, timeout = 15e3) {
    const bag = new Disposables(), apply = win.Reflect.apply;
    let busy = false, done = false;
    const cancel = /* @__PURE__ */ __name(() => {
      done = true;
      bag.clear();
    }, "cancel");
    patchMethod(win.Object, "keys", (original) => function(value) {
      if (!done && !busy) {
        busy = true;
        try {
          if (read(read(value, "mp5"), "type") === "gun" && read(read(value, "bullet_mp5"), "type") === "bullet" && read(read(value, "frag"), "type") === "throwable" && read(read(value, "explosion_frag"), "type") === "explosion") {
            cancel();
            win.queueMicrotask(() => onDefs(value));
          }
        } catch {
        } finally {
          busy = false;
        }
      }
      return apply(original, this, arguments);
    }, bag);
    const timer = win.setTimeout(cancel, timeout);
    bag.add(() => win.clearTimeout(timer));
    return cancel;
  }
  __name(captureDefinitions, "captureDefinitions");

  // src/esp.mjs
  var ESP_PALETTE = Object.freeze({ enemy: "#ff6262", ally: "#56b6ff", unknown: "#b9bfc9", target: "#ffd166" });
  var colorValue = /* @__PURE__ */ __name((value) => typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value), "colorValue");
  function safeLabel(value, limit = 24) {
    if (typeof value !== "string") return "";
    return [...value.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]/g, "").replace(/\s+/g, " ").trim()].slice(0, limit).join("");
  }
  __name(safeLabel, "safeLabel");
  function playerName(player) {
    const text = read(player, "nameText");
    return safeLabel(read(text, "text") ?? read(text, "_text"));
  }
  __name(playerName, "playerName");
  function espColor(kind, config, selected = false) {
    const key = selected ? "target" : kind;
    const custom = config[{ enemy: "espEnemyColor", ally: "espAllyColor", unknown: "espUnknownColor", target: "espTargetColor" }[key]];
    return colorValue(custom) ? custom : ESP_PALETTE[key] || ESP_PALETTE.unknown;
  }
  __name(espColor, "espColor");
  function edgeIndicator(point2, width, height, margin = 18) {
    if (!vec(point2) || !finite(width) || !finite(height) || width <= margin * 2 || height <= margin * 2) return null;
    const cx = width / 2, cy = height / 2, dx = point2.x - cx, dy = point2.y - cy;
    const tx = dx ? (cx - margin) / Math.abs(dx) : Infinity;
    const ty = dy ? (cy - margin) / Math.abs(dy) : Infinity;
    const t = Math.min(tx, ty);
    if (!finite(t)) return null;
    return { x: cx + dx * t, y: cy + dy * t, angle: Math.atan2(dy, dx) };
  }
  __name(edgeIndicator, "edgeIndicator");
  function emptyEspStats(state = "disabled") {
    return { state, considered: 0, drawn: 0, enemy: 0, ally: 0, unknown: 0, downed: 0, otherLayer: 0, offscreen: 0, labels: 0, labelsSkipped: 0, culled: 0 };
  }
  __name(emptyEspStats, "emptyEspStats");
  function buildEspFrame(mapping, players, config, width, height, target = null) {
    const stats = emptyEspStats("ready"), rows = [];
    if (!mapping?.active || !mapping.schema || !mapping.camera) return { origin: null, rows, stats: { ...stats, state: "waiting-mapping" } };
    const ownPos = overlayPosition(mapping.active, mapping), origin = project(mapping.camera, ownPos);
    if (!origin || !vec(ownPos)) return { origin: null, rows, stats: { ...stats, state: "invalid-projection" } };
    const relations = teamRelations(mapping.barn, mapping.active.__id);
    const reject = /* @__PURE__ */ __name(() => {
      stats.culled++;
    }, "reject");
    const maxDistance = finite(config.espMaxDistance) ? config.espMaxDistance : 200;
    for (const player of players.slice(0, 256)) {
      if (player === mapping.active) continue;
      stats.considered++;
      if (read(player, "active") !== true || at2(player, [mapping.schema.netKey, mapping.schema.deadKey])) {
        reject();
        continue;
      }
      const relation = relations.classify(read(player, "__id"));
      if (relation.kind === "self") {
        reject();
        continue;
      }
      if (relation.kind === "ally" && config.espShowAllies === false || relation.kind === "enemy" && config.espShowEnemies === false || relation.kind === "unknown" && config.espShowUnknown === false) {
        reject();
        continue;
      }
      const downed = read(player, "downed") === true;
      if (downed && config.espShowDowned === false) {
        reject();
        continue;
      }
      const knownLayer = finite(read(player, "layer")) && finite(read(mapping.active, "layer"));
      const layerMatch = knownLayer && sameLayer(player.layer, mapping.active.layer);
      if (!layerMatch && config.espSameLayerOnly) {
        reject();
        continue;
      }
      const pos = overlayPosition(player, mapping), screen = project(mapping.camera, pos);
      if (!screen || !vec(pos)) {
        reject();
        continue;
      }
      const distance = Math.hypot(pos.x - ownPos.x, pos.y - ownPos.y);
      if (!finite(distance) || distance > maxDistance) {
        reject();
        continue;
      }
      const offscreen = screen.x < 0 || screen.x > width || screen.y < 0 || screen.y > height;
      const edge = offscreen && config.espOffscreen ? edgeIndicator(screen, width, height) : null;
      if (offscreen && !edge) {
        reject();
        continue;
      }
      const selected = config.espHighlightTarget !== false && player === target && relation.kind === "enemy";
      const title = relation.kind === "ally" ? relation.squad ? "SQUAD" : "ALLY" : relation.kind === "enemy" ? "ENEMY" : "UNKNOWN";
      const parts = [title];
      if (config.nametags) {
        const name = playerName(player);
        if (name) parts.push(name);
      }
      if (downed) parts.push("DOWNED");
      if (!layerMatch) parts.push(knownLayer ? "OTHER LAYER" : "LAYER ?");
      if (config.espDistance) parts.push(`${Math.round(distance)} wu`);
      if (config.espWeapons) {
        const weapon = safeLabel(at2(player, [mapping.schema.netKey, mapping.schema.weaponKey]), 20);
        if (weapon) parts.push(weapon);
      }
      rows.push({
        player,
        relation: relation.kind,
        squad: relation.squad,
        selected,
        downed,
        offscreen,
        layerMatch,
        screen: edge || screen,
        color: espColor(relation.kind, config, selected),
        dash: !layerMatch ? [7, 4] : relation.kind === "unknown" ? [2, 4] : downed ? [3, 2] : [],
        distance,
        label: parts.join(" · ")
      });
      stats.drawn++;
      stats[relation.kind]++;
      if (downed) stats.downed++;
      if (!layerMatch) stats.otherLayer++;
      if (offscreen) stats.offscreen++;
    }
    if (players.length > 256) stats.culled += players.length - 256;
    return { origin, rows, stats };
  }
  __name(buildEspFrame, "buildEspFrame");
  function prepareOverlay(canvas, ctx, width, height, devicePixelRatio = 1) {
    const dpr = finite(devicePixelRatio) ? clamp(devicePixelRatio, 1, 2) : 1;
    if (!finite(width) || !finite(height) || width <= 0 || height <= 0) return false;
    const w = Math.round(width * dpr), h = Math.round(height * dpr);
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    if (canvas.style) {
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return true;
  }
  __name(prepareOverlay, "prepareOverlay");
  function overlaps(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
  }
  __name(overlaps, "overlaps");
  function placeLabel(anchor, w, h, width, height, occupied) {
    if (w > width - 8 || h > height - 8) return null;
    for (const [dx, dy] of [[12, -h - 6], [12, 8], [-w - 12, -h - 6], [-w - 12, 8]]) {
      const box = { x: clamp(anchor.x + dx, 4, width - w - 4), y: clamp(anchor.y + dy, 4, height - h - 4), w, h };
      if (!occupied.some((other) => overlaps(box, other))) {
        occupied.push(box);
        return box;
      }
    }
    return null;
  }
  __name(placeLabel, "placeLabel");
  var EspRenderer = class {
    static {
      __name(this, "EspRenderer");
    }
    widths = /* @__PURE__ */ new Map();
    reset() {
      this.widths.clear();
    }
    measure(ctx, text) {
      const key = `${ctx.font}\0${text}`;
      if (!this.widths.has(key)) {
        if (this.widths.size >= 256) this.widths.delete(this.widths.keys().next().value);
        this.widths.set(key, ctx.measureText(text).width);
      }
      return this.widths.get(key);
    }
    draw(ctx, frame, config, width, height) {
      if (!frame.origin) return frame.stats;
      const occupied = [], fontSize = finite(config.espFontSize) ? config.espFontSize : 12;
      ctx.save();
      try {
        ctx.font = `${fontSize}px system-ui, sans-serif`;
        ctx.textBaseline = "top";
        ctx.textAlign = "left";
        ctx.globalAlpha = (finite(config.espOpacity) ? config.espOpacity : 85) / 100;
        ctx.lineWidth = finite(config.espLineWidth) ? config.espLineWidth : 1.5;
        if (config.espLegend) {
          const items = [["enemy", "ENEMY"], ["ally", "ALLY / SQUAD"], ["unknown", "UNKNOWN"]];
          let y = 12;
          for (const [kind, text] of items) {
            const label = `${text}: ${frame.stats[kind]}`, w = this.measure(ctx, label) + 12, h = fontSize + 6;
            occupied.push({ x: 12, y, w, h });
            ctx.fillStyle = "#081b2b";
            ctx.fillRect(12, y, w, h);
            ctx.fillStyle = espColor(kind, config);
            ctx.fillText(label, 18, y + 3);
            y += h + 2;
          }
        }
        const rows = [...frame.rows].sort((a, b) => Number(b.selected) - Number(a.selected) || a.distance - b.distance);
        for (const row of rows) {
          const p = row.screen;
          ctx.strokeStyle = row.color;
          ctx.fillStyle = row.color;
          ctx.setLineDash(row.dash);
          if (config.lines) {
            ctx.beginPath();
            ctx.moveTo(frame.origin.x, frame.origin.y);
            ctx.lineTo(p.x, p.y);
            ctx.stroke();
          }
          if (row.offscreen) {
            const a = p.angle, cos = Math.cos(a), sin = Math.sin(a);
            ctx.beginPath();
            ctx.moveTo(p.x + cos * 8, p.y + sin * 8);
            ctx.lineTo(p.x - cos * 6 - sin * 5, p.y - sin * 6 + cos * 5);
            ctx.lineTo(p.x - cos * 6 + sin * 5, p.y - sin * 6 - cos * 5);
            ctx.closePath();
            ctx.stroke();
          } else if (config.espMarkers) {
            ctx.beginPath();
            ctx.arc(p.x, p.y, row.selected ? 11 : 7, 0, Math.PI * 2);
            ctx.stroke();
          }
          if (config.espLabels) {
            const w = this.measure(ctx, row.label) + 10, h = fontSize + 8;
            const box = placeLabel(p, w, h, width, height, occupied);
            if (!box) {
              frame.stats.labelsSkipped++;
              continue;
            }
            ctx.fillStyle = "#081b2b";
            ctx.fillRect(box.x, box.y, box.w, box.h);
            ctx.fillStyle = row.color;
            ctx.fillText(row.label, box.x + 5, box.y + 4);
            frame.stats.labels++;
          }
        }
        frame.stats.state = "drawn";
        return frame.stats;
      } finally {
        ctx.restore();
      }
    }
  };

  // src/features.mjs
  var VERIFIED_PROTOCOL = 1028;
  var PROJECTILE_TYPE = 9;
  var BULLET_HEIGHT = 0.25;
  function grenadeZone(entity, definitions, layer, protocol) {
    if (protocol !== VERIFIED_PROTOCOL || read(entity, "__type") !== PROJECTILE_TYPE || read(entity, "active") !== true) return null;
    const def = definitions?.[read(entity, "type")];
    if (def?.type !== "throwable" || !def.explosionType || def.explosionType === "explosion_smoke") return null;
    const explosion = definitions[def.explosionType], pos = read(entity, "pos");
    if (explosion?.type !== "explosion" || !finite(explosion?.rad?.max) || explosion.rad.max <= 0 || !vec(pos) || !sameLayer(read(entity, "layer"), layer)) return null;
    return { pos, radius: explosion.rad.max };
  }
  __name(grenadeZone, "grenadeZone");
  function localDataSchema(game, player) {
    const candidates = [];
    for (const [, child] of entries(game)) {
      const tree = ast(readMethod(child, "getAimMovement"));
      const root = tree?.params?.[0]?.name;
      if (!root) continue;
      for (const p of paths(tree, root)) {
        if (p.length !== 2 || !Number.isInteger(at2(player, p)) || at2(player, p) < 0 || at2(player, p) > 3) continue;
        const data2 = read(player, p[0]);
        const weapons = entries(data2).filter(([, v]) => Array.isArray(v) && v.length >= 4 && v.every((w) => typeof read(w, "type") === "string" && finite(read(w, "ammo"))));
        if (weapons.length !== 1) continue;
        const zoomKeys = [];
        for (const [, fn] of methods(player)) {
          const tree2 = ast(fn);
          let indexOf = false;
          walk(tree2, (n) => {
            if (n.type === "MemberExpression" && n.property?.name === "indexOf") indexOf = true;
          });
          if (indexOf) {
            for (const q of paths(tree2)) if (q.length === 2 && q[0] === p[0] && finite(at2(player, q))) zoomKeys.push(q[1]);
          }
        }
        candidates.push({ data: data2, dataKey: p[0], slotKey: p[1], weaponsKey: weapons[0][0], zoomKey: unique(zoomKeys) });
      }
    }
    return candidates.length === 1 ? candidates[0] : null;
  }
  __name(localDataSchema, "localDataSchema");
  var Overrides = class {
    static {
      __name(this, "Overrides");
    }
    records = /* @__PURE__ */ new Map();
    owned = /* @__PURE__ */ new WeakMap();
    getRaw(owner, key) {
      return this.owned.get(owner)?.get(key)?.raw ?? read(owner, key);
    }
    set(owner, key, transform) {
      let keys = this.owned.get(owner);
      if (keys?.has(key)) {
        keys.get(key).transform = transform;
        return true;
      }
      const d = Object.getOwnPropertyDescriptor(owner, key);
      if (!d || !("value" in d) || !d.configurable || !d.writable) return false;
      const record = { owner, key, descriptor: d, raw: d.value, transform };
      record.get = () => record.transform(record.raw);
      record.set = (value) => {
        record.raw = value;
      };
      try {
        Object.defineProperty(owner, key, { configurable: true, enumerable: d.enumerable, get: record.get, set: record.set });
      } catch {
        return false;
      }
      if (!keys) this.owned.set(owner, keys = /* @__PURE__ */ new Map());
      keys.set(key, record);
      this.records.set(record, record);
      return true;
    }
    release(owner, key) {
      const r = this.owned.get(owner)?.get(key);
      if (!r) return;
      const now = Object.getOwnPropertyDescriptor(owner, key);
      if (now?.get === r.get && now?.set === r.set) Object.defineProperty(owner, key, { ...r.descriptor, value: r.raw });
      this.owned.get(owner).delete(key);
      this.records.delete(r);
    }
    prune(keep) {
      for (const r of this.records.values()) if (!keep(r.owner, r.key)) this.release(r.owner, r.key);
    }
    clear() {
      this.prune(() => false);
    }
  };
  function inputShape(data2) {
    return object(data2) && typeof data2.shootStart === "boolean" && typeof data2.shootHold === "boolean" && ["moveLeft", "moveRight", "moveUp", "moveDown", "touchMoveActive"].every((k) => typeof data2[k] === "boolean") && vec(data2.toMouseDir) && vec(data2.touchMoveDir) && finite(data2.toMouseLen) && Array.isArray(data2.inputs) && data2.inputs.length <= 7 && data2.inputs.every(Number.isInteger) && typeof data2.serialize === "function" && typeof data2.addInput === "function";
  }
  __name(inputShape, "inputShape");
  function modifyMessage(data2, config, context) {
    if (!inputShape(data2) || context.protocol !== VERIFIED_PROTOCOL) return data2;
    const copy = Object.assign(Object.create(Object.getPrototypeOf(data2)), data2, {
      inputs: [...data2.inputs],
      touchMoveDir: point(data2.touchMoveDir),
      toMouseDir: point(data2.toMouseDir)
    });
    if (config.mobileMovement) {
      const x = Number(data2.moveRight) - Number(data2.moveLeft), y = Number(data2.moveUp) - Number(data2.moveDown);
      const len = Math.hypot(x, y);
      if (len) {
        copy.touchMoveActive = true;
        copy.touchMoveLen = 255;
        copy.touchMoveDir = { x: x / len, y: y / len };
      }
    }
    if (config.melee && context.meleeDirection && vec(context.meleeDirection)) {
      copy.touchMoveActive = true;
      copy.touchMoveLen = 255;
      copy.touchMoveDir = point(context.meleeDirection);
    }
    if (context.switchSlot !== null && context.switchSlot !== void 0) copy.addInput(context.switchSlot === 0 ? 11 : 12);
    return copy;
  }
  __name(modifyMessage, "modifyMessage");
  var Features = class {
    static {
      __name(this, "Features");
    }
    constructor(win, app, config, report, definitions = null) {
      this.win = win;
      this.app = app;
      this.config = config;
      this.report = report;
      this.definitions = definitions;
      this.hooks = new Disposables();
      this.matchHooks = new Disposables();
      this.overrides = new Overrides();
      this.tracker = new Tracker();
      this.protocol = null;
      this.mapping = null;
      this.local = null;
      this.target = null;
      this.dot = null;
      this.restoreMouse = null;
      this.lastMap = -Infinity;
      this.lastVisual = -Infinity;
      this.lastInput = -Infinity;
      this.lastScan = -Infinity;
      this.effects = [];
      this.lastGame = null;
      this.lastPool = null;
      this.lastActive = null;
      this.lastActiveId = null;
      this.stopped = false;
      this.keys = /* @__PURE__ */ new Set();
      this.holdAim = false;
      this.nextSemi = 0;
      this.frameId = 0;
      this.semiFrame = -1;
      this.semiValue = false;
      this.nextSwitch = 0;
      this.switchSlot = null;
      this.meleeDirection = null;
      this.lastAmmo = null;
      this.stats = { frames: 0, mappingRuns: 0, featureMs: 0, lastError: null, aimState: "disabled", aimRejections: {} };
      this.joinState = { observed: false, forwarded: false, mobile: null, requested: false };
      this.capabilities = {};
      this.failed = /* @__PURE__ */ new Set();
      this.lootSource = null;
      this.pickupPulse = false;
      this.nextPickup = 0;
      this.pickupAttempt = null;
      this.stats.lootState = "disabled";
      this.stats.pickupPulses = 0;
      this.espRenderer = new EspRenderer();
      this.stats.esp = emptyEspStats();
      this.installFlush();
      const ticker = app.pixi.ticker;
      const pre = /* @__PURE__ */ __name(() => this.guard("input-frame", () => this.pre()), "pre");
      const post = /* @__PURE__ */ __name(() => this.guard("visual-frame", () => this.post()), "post");
      ticker.add(pre, null, 10);
      ticker.add(post, null, -20);
      this.hooks.add(() => ticker.remove(pre, null));
      this.hooks.add(() => ticker.remove(post, null));
      this.reconcile(true);
    }
    guard(name, fn) {
      if (this.stopped || this.failed.has(name)) return;
      try {
        fn();
      } catch (e) {
        this.failed.add(name);
        this.stats.lastError = `${name}: ${e.message}`;
        if (name === "visual-frame") this.stats.esp = emptyEspStats("error");
        this.restoreInput();
        this.overrides.clear();
        this.clearCanvas();
        this.report("error", this.stats.lastError);
      }
    }
    installFlush() {
      if (!this.app.input || !patchMethod(this.app.input, "flush", (original) => {
        const self = this;
        return function() {
          self.restoreInput();
          return Reflect.apply(original, this, arguments);
        };
      }, this.hooks)) this.report("warning", "Không có flush contract: aim input bị khóa.");
      else this.flushReady = true;
    }
    restoreInput() {
      if (this.restoreMouse) {
        const { owner, x, y } = this.restoreMouse;
        if (owner.x === this.restoreMouse.appliedX) owner.x = x;
        if (owner.y === this.restoreMouse.appliedY) owner.y = y;
        this.restoreMouse = null;
      }
    }
    releaseMatch() {
      this.restoreInput();
      this.matchHooks.clear();
      this.overrides.clear();
      this.tracker.reset();
      this.target = null;
      this.dot = null;
      this.meleeDirection = null;
      this.switchSlot = null;
      this.lastAmmo = null;
      this.local = null;
      this.mapping = null;
      this.effects = [];
      this.lootSource = null;
      this.pickupPulse = false;
      this.pickupAttempt = null;
      this.nextPickup = 0;
      this.binds = null;
      this.bindsInstalled = false;
      this.stickyId = null;
      this.lastInput = -Infinity;
      this.espRenderer.reset();
      this.stats.esp = emptyEspStats("waiting-mapping");
      this.clearCanvas();
    }
    installSender(game) {
      const key = discoverSender(game);
      this.senderReady = false;
      if (!key) return;
      const self = this;
      this.senderReady = patchMethod(game, key, (original) => function(type, data2, ...rest) {
        let outgoing = data2, joinRecord = null;
        try {
          if (type === 1 && Number.isInteger(data2?.protocol) && typeof data2.name === "string" && typeof data2.joinToken === "string" && (typeof data2.isMobile === "boolean" || data2.isMobile === void 0) && typeof data2.useTouch === "boolean" && typeof data2.serialize === "function") {
            self.protocol = data2.protocol;
            self.lastMap = -Infinity;
            if (self.protocol === VERIFIED_PROTOCOL && self.config.autoLoot && self.config.lootMode === "mobile") {
              outgoing = Object.assign(Object.create(Object.getPrototypeOf(data2)), data2, { isMobile: true });
            }
            joinRecord = { observed: true, forwarded: false, mobile: !!outgoing.isMobile, requested: !!self.config.autoLoot && self.config.lootMode === "mobile" };
            self.joinState = joinRecord;
            self.report("protocol", `Join protocol ${self.protocol}; mobile loot ${self.config.autoLoot && self.config.lootMode === "mobile" ? "yêu cầu bật" : "tắt"}.`);
          }
          if (type === 3 && !self.stopped && self.mapping?.ui?.spectating === false) {
            outgoing = modifyMessage(data2, self.config, self);
            self.switchSlot = null;
          }
        } catch (e) {
          self.report("warning", `Input bypassed: ${e.message}`);
          outgoing = data2;
        }
        const result = Reflect.apply(original, this, [type, outgoing, ...rest]);
        if (joinRecord) joinRecord.forwarded = true;
        return result;
      }, this.gameHooks);
    }
    reconcile(force = false) {
      const now = this.win.performance.now(), game = this.app.game;
      if (game !== this.lastGame) {
        this.releaseMatch();
        this.gameHooks?.clear();
        this.gameHooks = new Disposables();
        this.lastGame = game;
        this.protocol = null;
        this.lastPool = null;
        this.lastActive = null;
        this.joinState = { observed: false, forwarded: false, mobile: null, requested: false };
        if (game) this.installSender(game);
      }
      if (!game?.initialized) {
        if (this.mapping) this.releaseMatch();
        this.capabilities = { sender: this.senderReady, visuals: false };
        return;
      }
      if (!force && now - this.lastMap < 1e3 && this.mapping) return;
      this.lastMap = now;
      this.stats.mappingRuns++;
      const next = discover(game);
      if (next.pool !== this.lastPool || next.active !== this.lastActive || next.active?.__id !== this.lastActiveId) {
        this.releaseMatch();
        this.failed.clear();
        this.lastPool = next.pool;
        this.lastActive = next.active;
        this.lastActiveId = next.active?.__id;
      }
      this.mapping = next;
      if (next.active && !this.local) this.local = localDataSchema(game, next.active);
      const nextBinds = this.findBinds();
      if (this.binds && this.binds !== nextBinds) {
        this.matchHooks.clear();
        this.bindsInstalled = false;
        this.nextSemi = 0;
        this.semiFrame = -1;
      }
      this.binds = nextBinds;
      this.lootSource = discoverLootSource(game);
      const ready = !!(next.schema && next.camera && next.barn && next.pool && next.active?.active);
      this.capabilities = {
        visuals: ready,
        interpolatedOverlay: ready && !!next.visualPosKey,
        grenadeZones: ready && !!this.definitions && !!next.registryKey && this.protocol === VERIFIED_PROTOCOL,
        aim: ready && this.flushReady && !!next.ui,
        autoPickup: ready && !!next.ui && !!this.lootSource && !!this.binds && !!this.definitions && this.protocol === VERIFIED_PROTOCOL,
        prediction: ready && !!this.definitions,
        wallcheck: !!next.creator && !!next.registryKey,
        zoom: !!this.local?.zoomKey,
        semi: !!this.binds && !!this.definitions && this.protocol === VERIFIED_PROTOCOL,
        sender: this.senderReady,
        mobile: this.senderReady && this.protocol === VERIFIED_PROTOCOL,
        switch: !!this.local && !!this.definitions && this.protocol === VERIFIED_PROTOCOL
      };
      if (!this.bindsInstalled && this.capabilities.semi) this.installSemi();
      this.report("mapping", ready ? "Mapping hợp lệ; tính năng thiếu contract sẽ bị khóa." : "Chờ player/camera contract hoặc build chưa tương thích.");
    }
    findBinds() {
      return unique(entries(this.app.game).filter(([, o]) => typeof readMethod(o, "isBindDown") === "function" && typeof readMethod(o, "isBindPressed") === "function" && object(read(o, "input"))).map(([, o]) => o));
    }
    installSemi() {
      const binds = this.binds;
      if (!binds) return;
      const self = this;
      this.bindsInstalled = patchMethod(binds, "isBindPressed", (original) => function(code) {
        const actual = Reflect.apply(original, this, arguments);
        if (code === 10 && self.pickupPulse && !self.stopped && !self.failed.has("input-frame") && self.config.autoLoot && self.config.lootMode === "nearby" && self.protocol === VERIFIED_PROTOCOL && self.mapping?.ui?.spectating === false && !self.win.document.hidden) return true;
        if (self.protocol === VERIFIED_PROTOCOL && self.config.autoSwitch && self.switchSlot !== null && self.mapping?.ui?.spectating === false && code === (self.switchSlot === 0 ? 11 : 12)) return true;
        if (code !== 4 || self.failed.has("input-frame") || !self.config.semi || self.protocol !== VERIFIED_PROTOCOL || !self.mapping?.active || self.mapping.ui?.spectating !== false) return actual;
        const gun = self.definitions?.[localWeapon(self.mapping)];
        if (gun?.type !== "gun" || gun.fireMode !== "single") return actual;
        if (!this.isBindDown(4)) {
          self.nextSemi = 0;
          self.semiFrame = -1;
          return actual;
        }
        if (self.semiFrame === self.frameId) return actual || self.semiValue;
        self.semiFrame = self.frameId;
        self.semiValue = false;
        const now = self.win.performance.now();
        if (now >= self.nextSemi) {
          self.nextSemi = now + Math.max(50, (gun.fireDelay || 0.1) * 1e3);
          self.semiValue = true;
          return true;
        }
        return actual;
      }, this.matchHooks);
      if (this.bindsInstalled) this.matchHooks.add(() => {
        this.bindsInstalled = false;
      });
    }
    blocked(from, to, bulletPath = true) {
      if (!this.config.wallcheck) return false;
      if (!this.capabilities.wallcheck) return true;
      return this.mapping.obstacles().some((o) => !read(o, "dead") && read(o, "collidable") && !(bulletPath && this.protocol === VERIFIED_PROTOCOL && finite(read(o, "height")) && read(o, "height") < BULLET_HEIGHT) && (!finite(read(o, "layer")) || sameLayer(read(o, "layer"), from.layer)) && segmentBlocked(from.pos, to.pos, read(o, "collider")));
    }
    pre() {
      this.frameId++;
      this.restoreInput();
      const staleIdentity = this.mapping && (read(this.app.game, this.mapping.barnKey) !== this.mapping.barn || read(this.mapping.barn, "playerPool") !== this.mapping.pool || this.mapping.activeKey && read(this.app.game, this.mapping.activeKey) !== this.mapping.active || this.mapping.active && this.mapping.active.__id !== this.lastActiveId || this.local && this.mapping.active[this.local.dataKey] !== this.local.data);
      if (staleIdentity) {
        this.releaseMatch();
        this.lastActive = null;
      }
      this.reconcile(!!staleIdentity);
      this.updateLoot();
      const m = this.mapping, cfg = this.config;
      this.target = null;
      this.dot = null;
      this.meleeDirection = null;
      this.stats.aimRejections = {};
      this.stats.aimState = cfg.aim || cfg.melee ? "waiting-mapping" : "disabled";
      if (!cfg.aim && !cfg.melee && !cfg.autoSwitch) return;
      if (!m?.schema || !m.active?.active) return;
      if (m.ui?.spectating !== false) {
        this.stats.aimState = m.ui ? "spectating" : "missing-spectator-contract";
        return;
      }
      if (this.win.document.hidden) {
        this.stats.aimState = "page-hidden";
        return;
      }
      const now = this.win.performance.now(), self = m.active, schema = m.schema;
      const pos = read(self, schema.posKey), mouse = this.app.input?.mousePos;
      if (!vec(pos) || !vec(mouse)) {
        this.stats.aimState = "invalid-input-position";
        return;
      }
      if (at2(self, [schema.netKey, schema.deadKey])) {
        this.stats.aimState = "dead";
        return;
      }
      this.updateSwitch();
      if (!cfg.aim && !cfg.melee) return;
      const relations = teamRelations(m.barn, self.__id);
      if (!relations.ready) {
        this.stats.aimState = "missing-own-team";
        return;
      }
      const players = m.players();
      for (const p of players) {
        const v = read(p, schema.posKey);
        if (vec(v)) this.tracker.update(p, v, now);
      }
      const bindDown = this.protocol === VERIFIED_PROTOCOL && this.binds ? this.binds.isBindDown(4) : !!this.app.input.mouseButtons?.[0];
      const firing = !!bindDown;
      const wantMelee = cfg.melee && this.capabilities.mobile && firing && this.definitions?.[localWeapon(m)]?.type === "melee";
      if ((!cfg.aim || !this.capabilities.aim || !firing) && !wantMelee) {
        this.stats.aimState = !firing ? "fire-not-held" : "missing-aim-contract";
        return;
      }
      if (cfg.wallcheck && !this.capabilities.wallcheck) {
        this.stats.aimState = "wallcheck-unavailable";
        return;
      }
      const candidates = [], rejected = this.stats.aimRejections;
      const reject = /* @__PURE__ */ __name((reason) => {
        rejected[reason] = (rejected[reason] || 0) + 1;
      }, "reject");
      for (const p of players) {
        if (p === self) continue;
        if (at2(p, [schema.netKey, schema.deadKey])) {
          reject("dead");
          continue;
        }
        if (!cfg.knocked && p.downed) {
          reject("downed");
          continue;
        }
        if (!sameLayer(p.layer, self.layer)) {
          reject("otherLayer");
          continue;
        }
        const relation = relations.classify(p.__id), targetPos = read(p, schema.posKey);
        if (relation.kind === "unknown") {
          reject("unknownTeam");
          continue;
        }
        if (relation.kind !== "enemy") {
          reject("teammate");
          continue;
        }
        if (!vec(targetPos)) {
          reject("invalidPosition");
          continue;
        }
        const screen2 = project(m.camera, targetPos);
        if (!screen2) {
          reject("invalidProjection");
          continue;
        }
        const distance = wantMelee ? Math.hypot(pos.x - targetPos.x, pos.y - targetPos.y) : Math.hypot(screen2.x - mouse.x, screen2.y - mouse.y);
        if (distance > (wantMelee ? 5.5 : cfg.fov)) {
          reject("outsideFov");
          continue;
        }
        if (this.blocked({ pos, layer: self.layer }, { pos: targetPos }, !wantMelee)) {
          reject("wall");
          continue;
        }
        candidates.push({ p, pos: targetPos, screen: screen2, distance });
      }
      candidates.sort((a, b) => a.distance - b.distance);
      let target = cfg.sticky && this.stickyId !== null ? candidates.find((c) => c.p.__id === this.stickyId) : null;
      target ||= candidates[0];
      if (!target) {
        this.stickyId = null;
        this.stats.aimState = "no-candidate";
        return;
      }
      this.stickyId = target.p.__id;
      let world = point(target.pos);
      if (cfg.predict && this.capabilities.prediction && !wantMelee) {
        const gun = this.definitions[localWeapon(m)], bullet = this.definitions[gun?.bulletType];
        const track = this.tracker.states.get(target.p);
        if (track && bullet?.speed > 0) {
          const relative = { x: target.pos.x - pos.x, y: target.pos.y - pos.y };
          const time = intercept(relative, { x: track.vx, y: track.vy }, bullet.speed);
          if (time !== null) world = { x: world.x + track.vx * time, y: world.y + track.vy * time };
        }
      }
      const screen = aimPoint(m.camera, world, pos);
      if (!screen || !this.flushReady) {
        this.stats.aimState = "missing-input-contract";
        return;
      }
      const dt = clamp((now - this.lastInput) / 1e3, 1e-3, 0.05);
      this.lastInput = now;
      const gain = cfg.smoothEnabled ? 1 - Math.exp(-dt / (0.015 + cfg.smooth / 500)) : 1;
      const x = mouse.x + (screen.x - mouse.x) * gain, y = mouse.y + (screen.y - mouse.y) * gain;
      this.restoreMouse = { owner: mouse, x: mouse.x, y: mouse.y, appliedX: x, appliedY: y };
      mouse.x = x;
      mouse.y = y;
      this.target = target.p;
      this.dot = { x, y };
      this.stats.aimState = "applied";
      if (wantMelee) {
        const dx = target.pos.x - pos.x, dy = target.pos.y - pos.y, len = Math.hypot(dx, dy);
        if (len > 0.1) this.meleeDirection = { x: dx / len, y: dy / len };
      }
    }
    updateSwitch() {
      if (!this.config.autoSwitch || !this.capabilities.switch || !this.local) return;
      const { data: data2, slotKey, weaponsKey } = this.local;
      const slot = data2[slotKey], weapons = data2[weaponsKey], current2 = weapons?.[slot];
      if (![0, 1].includes(slot) || !current2) {
        this.lastAmmo = null;
        return;
      }
      const def = this.definitions[current2.type], now = this.win.performance.now();
      if (def?.type === "gun" && def.fireMode === "single" && this.lastAmmo?.slot === slot && this.lastAmmo.type === current2.type && current2.ammo < this.lastAmmo.ammo && now >= this.nextSwitch) {
        const other = weapons[1 - slot];
        if (other?.ammo > 0 && this.definitions[other.type]?.type === "gun") {
          this.switchSlot = 1 - slot;
          this.nextSwitch = now + 200;
        }
      }
      this.lastAmmo = { slot, ammo: current2.ammo, type: current2.type };
    }
    scanEffects() {
      const m = this.mapping, out = [], seen = /* @__PURE__ */ new Set();
      if (!m) return;
      const roots = [m.map, ...entries(this.app.game).map(([, v]) => v).filter((v) => typeof readMethod(v, "m_allocParticle") === "function")];
      roots.push(...entries(this.app.game).map(([, v]) => v).filter((v) => entries(v).some(([, a]) => Array.isArray(a) && a.some((p) => read(read(p, "sprite"), "texture") || read(p, "fadeTicker") !== void 0))));
      let budget = 12e3;
      const visit = /* @__PURE__ */ __name((o, depth) => {
        if (!object(o) || depth < 0 || seen.has(o) || --budget < 0) return;
        seen.add(o);
        const sprite = read(o, "sprite");
        if (sprite && typeof read(o, "type") === "string" && /^(tree|bush|table|stairs)[_-]/.test(read(o, "type"))) out.push({ owner: sprite, kind: "tree", entity: o });
        if (read(o, "isCeiling") === true && sprite) out.push({ owner: sprite, kind: "ceiling", entity: o });
        if (sprite && finite(read(o, "fadeTicker")) && finite(read(o, "fadeDuration")) && vec(read(o, "posTarget"))) out.push({ owner: sprite, kind: "smoke", entity: o });
        for (const [k, v] of entries(o)) {
          if (["parent", "children", "container", "sprite", "texture", "_texture", "game", "renderer"].includes(k)) continue;
          if (Array.isArray(v)) {
            for (const child of v.slice(0, 2048)) visit(child, depth - 1);
          } else if (depth > 0 && object(v)) visit(v, depth - 1);
        }
      }, "visit");
      roots.forEach((root) => visit(root, 4));
      this.effects = out;
    }
    post() {
      this.restoreInput();
      const now = this.win.performance.now();
      this.stats.frames++;
      if (now - this.lastVisual < 1e3 / 30) return;
      this.lastVisual = now;
      const start2 = now, m = this.mapping, cfg = this.config;
      this.clearCanvas();
      this.stats.esp = emptyEspStats(cfg.esp ? this.win.document.hidden ? "page-hidden" : this.ctx ? "waiting-mapping" : "no-canvas" : "disabled");
      if (!this.app.game?.initialized || !m?.schema || !m.active?.active || !this.capabilities.visuals || this.win.document.hidden) {
        this.overrides.clear();
        return;
      }
      if (!(cfg.esp || cfg.xray || cfg.zoom || cfg.aim || cfg.melee || cfg.ownFlashlight || cfg.grenadeZones)) {
        if (this.overrides.records.size) this.overrides.clear();
        return;
      }
      const players = m.players();
      const espFrame = cfg.esp && this.ctx ? buildEspFrame(m, players, cfg, this.win.innerWidth, this.win.innerHeight, this.target) : null;
      const espPlayers = new Set(espFrame?.rows.filter((row) => !row.offscreen).map((row) => row.player));
      const keep = /* @__PURE__ */ new Map();
      const want = /* @__PURE__ */ __name((owner, key) => {
        if (!keep.has(owner)) keep.set(owner, /* @__PURE__ */ new Set());
        keep.get(owner).add(key);
      }, "want");
      for (const p of players) {
        if (!p.nameText || p === m.active || at2(p, [m.schema.netKey, m.schema.deadKey])) continue;
        if (cfg.esp && cfg.nametags && espPlayers.has(p)) {
          this.overrides.set(p.nameText, "visible", () => !cfg.espLabels);
          want(p.nameText, "visible");
        }
      }
      if (cfg.xray && now - this.lastScan > 500) {
        this.scanEffects();
        this.lastScan = now;
      }
      for (const effect of cfg.xray ? this.effects : []) {
        const { owner, kind, entity } = effect;
        if (read(entity, "active") === false || owner.destroyed) continue;
        if (kind === "ceiling" && cfg.ceilings && read(entity, "isCeiling") === true) {
          this.overrides.set(owner, "visible", () => false);
          want(owner, "visible");
        }
        if (kind === "tree" && /^(tree|bush|table|stairs)[_-]/.test(read(entity, "type") || "")) {
          this.overrides.set(owner, "alpha", (raw) => Math.min(raw, cfg.treeOpacity / 100));
          want(owner, "alpha");
        }
        if (kind === "smoke") {
          this.overrides.set(owner, "alpha", (raw) => raw * cfg.smokeOpacity / 100);
          want(owner, "alpha");
        }
      }
      if (cfg.zoom && this.local?.zoomKey) {
        const { data: data2, zoomKey } = this.local;
        this.overrides.set(data2, zoomKey, (raw) => raw * cfg.zoomFactor);
        want(data2, zoomKey);
      }
      this.overrides.prune((owner, key) => keep.get(owner)?.has(key));
      this.draw(players, espFrame);
      this.stats.featureMs = this.win.performance.now() - start2;
    }
    attachCanvas(canvas) {
      this.canvas = canvas;
      try {
        this.ctx = canvas.getContext("2d");
      } catch {
        this.ctx = null;
      }
      if (!this.ctx) this.report("warning", "Canvas 2D không khả dụng: overlay bị khóa, input features không bị dừng.");
    }
    clearCanvas() {
      if (this.ctx && this.canvas) this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    }
    draw(players, espFrame = null) {
      const ctx = this.ctx, canvas = this.canvas, m = this.mapping, cfg = this.config;
      if (!ctx || !canvas) return;
      const width = this.win.innerWidth, height = this.win.innerHeight;
      if (!prepareOverlay(canvas, ctx, width, height, this.win.devicePixelRatio)) return;
      ctx.globalAlpha = 1;
      ctx.setLineDash([]);
      const mouse = this.app.input?.mousePos;
      if (cfg.aim && cfg.showFov && vec(mouse)) {
        ctx.strokeStyle = "#ffffff44";
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(mouse.x, mouse.y, cfg.fov, 0, Math.PI * 2);
        ctx.stroke();
      }
      if (cfg.showDot && this.dot) {
        ctx.fillStyle = "#f95353";
        ctx.beginPath();
        ctx.arc(this.dot.x, this.dot.y, 4, 0, Math.PI * 2);
        ctx.fill();
      }
      const selfPos = overlayPosition(m.active, m), origin = project(m.camera, selfPos);
      if (!origin) {
        if (cfg.esp) this.stats.esp = emptyEspStats("invalid-projection");
        return;
      }
      if (cfg.esp) {
        espFrame ||= buildEspFrame(m, players, cfg, width, height, this.target);
        this.stats.esp = this.espRenderer.draw(ctx, espFrame, cfg, width, height);
      }
      if (cfg.ownFlashlight && this.definitions) {
        const gun = this.definitions[localWeapon(m)], bullet = this.definitions[gun?.bulletType];
        const aim = this.dot || mouse;
        if (gun?.type === "gun" && bullet?.distance > 0 && vec(aim)) {
          const angle = Math.atan2(aim.y - origin.y, aim.x - origin.x);
          const scale = read(m.camera.camera, m.camera.scaleKeys[0]) * read(m.camera.camera, m.camera.scaleKeys[1]);
          ctx.fillStyle = "#88caff18";
          ctx.beginPath();
          ctx.moveTo(origin.x, origin.y);
          const spread = clamp(gun.shotSpread || 0, 1, 90) * Math.PI / 180;
          ctx.arc(origin.x, origin.y, bullet.distance * scale, angle - spread / 2, angle + spread / 2);
          ctx.closePath();
          ctx.fill();
        }
      }
      if (cfg.grenadeZones && this.capabilities.grenadeZones) {
        for (const [, entity] of entries(read(m.creator, m.registryKey))) {
          const zone = grenadeZone(entity, this.definitions, m.active.layer, this.protocol);
          if (!zone) continue;
          const { pos, radius } = zone;
          const center = project(m.camera, pos);
          if (!center) continue;
          const scale = read(m.camera.camera, m.camera.scaleKeys[0]) * read(m.camera.camera, m.camera.scaleKeys[1]);
          ctx.strokeStyle = "#ff744a99";
          ctx.beginPath();
          ctx.arc(center.x, center.y, radius * scale, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
    }
    updateLoot() {
      this.pickupPulse = false;
      if (!this.config.autoLoot || this.config.lootMode === "mobile") return;
      const m = this.mapping, now = this.win.performance.now();
      if (!this.capabilities.autoPickup || !this.bindsInstalled) {
        this.stats.lootState = "missing-pickup-contract";
        return;
      }
      if (this.win.document.hidden || m.ui?.spectating !== false || !m.active?.active || m.active.downed || at2(m.active, [m.schema.netKey, m.schema.deadKey])) {
        this.stats.lootState = "paused";
        return;
      }
      const loot = read(this.lootSource.owner, this.lootSource.key), pos = read(m.active, m.schema.posKey);
      if (read(loot, "__type") !== 3 || read(loot, "active") !== true || !vec(read(loot, "pos")) || !vec(pos) || !sameLayer(read(loot, "layer"), m.active.layer) || !finite(read(loot, "rad")) || loot.rad <= 0 || !(loot.ownerId === 0 || loot.ownerId === m.active.__id) || Math.hypot(loot.pos.x - pos.x, loot.pos.y - pos.y) >= loot.rad) {
        this.stats.lootState = "no-nearby-loot";
        this.pickupAttempt = null;
        this.nextPickup = 0;
        return;
      }
      const def = this.definitions?.[read(loot, "type")];
      if (!["ammo", "heal", "boost", "throwable"].includes(def?.type)) {
        this.stats.lootState = "skip-non-supply";
        return;
      }
      const previous = this.pickupAttempt;
      const unchanged = previous?.entity === loot && previous.id === loot.__id && previous.count === loot.count;
      if (!unchanged) this.nextPickup = 0;
      if (now < this.nextPickup) {
        this.stats.lootState = "pickup-backoff";
        return;
      }
      const attempts = unchanged ? previous.attempts + 1 : 1;
      this.pickupAttempt = { entity: loot, id: loot.__id, count: loot.count, attempts };
      this.nextPickup = now + Math.min(2e3, 350 * 2 ** Math.min(attempts - 1, 3));
      this.pickupPulse = true;
      this.stats.pickupPulses++;
      this.stats.lootState = "loot-input-ready";
    }
    autoLootStatus() {
      if (!this.config.autoLoot) return this.joinState.mobile && this.joinState.forwarded ? "off-next-join" : "disabled";
      if (this.config.lootMode === "nearby") return this.stats.lootState;
      if (!this.senderReady) return "missing-sender";
      if (this.protocol !== null && this.protocol !== VERIFIED_PROTOCOL) return "unsupported-protocol";
      if (!this.joinState.observed || !this.joinState.mobile) return "pending-next-join";
      return this.joinState.forwarded ? "mobile-join-forwarded" : "join-not-forwarded";
    }
    diagnostics() {
      const m = this.mapping;
      const checks = {
        initialized: !!this.app.game?.initialized,
        playerBarn: !!m?.barn,
        playerPool: !!m?.poolKey,
        activePlayer: !!m?.active,
        playerSchema: !!m?.schema,
        camera: !!m?.camera,
        spectatorUI: !!m?.ui,
        inputFlush: !!this.flushReady,
        sender: !!this.senderReady,
        canvasRenderer: !!this.ctx,
        definitions: !!this.definitions,
        lootSource: !!this.lootSource,
        localData: !!this.local,
        binds: !!this.binds,
        protocolObserved: this.protocol !== null,
        protocolMatches: this.protocol === VERIFIED_PROTOCOL
      };
      return {
        version: "0.3.0",
        protocol: this.protocol,
        sourceProtocol: VERIFIED_PROTOCOL,
        initialized: checks.initialized,
        checks,
        autoLoot: { state: this.autoLootStatus(), mode: this.config.lootMode, ...this.joinState },
        missingContracts: Object.keys(checks).filter((key) => !checks[key]),
        capabilities: { ...this.capabilities },
        stats: { ...this.stats },
        failed: [...this.failed],
        overrides: this.overrides.records.size
      };
    }
    dispose() {
      if (this.stopped) return;
      this.stopped = true;
      this.releaseMatch();
      this.gameHooks?.clear();
      this.hooks.clear();
      this.canvas = this.ctx = null;
    }
  };

  // src/menu.mjs
  var DEFAULTS = Object.freeze({
    version: 1,
    aim: false,
    smoothEnabled: true,
    smooth: 50,
    knocked: false,
    sticky: true,
    showDot: true,
    fov: 100,
    showFov: true,
    wallcheck: true,
    predict: true,
    melee: false,
    autoSwitch: false,
    semi: false,
    xray: false,
    ceilings: true,
    smokeOpacity: 50,
    treeOpacity: 50,
    esp: false,
    nametags: true,
    lines: true,
    espShowAllies: true,
    espShowEnemies: true,
    espShowUnknown: true,
    espShowDowned: true,
    espSameLayerOnly: false,
    espLabels: true,
    espDistance: true,
    espWeapons: false,
    espMarkers: true,
    espOffscreen: false,
    espHighlightTarget: true,
    espLegend: true,
    espMaxDistance: 200,
    espFontSize: 12,
    espOpacity: 85,
    espLineWidth: 1.5,
    espEnemyColor: ESP_PALETTE.enemy,
    espAllyColor: ESP_PALETTE.ally,
    espUnknownColor: ESP_PALETTE.unknown,
    espTargetColor: ESP_PALETTE.target,
    ownFlashlight: false,
    grenadeZones: false,
    zoom: false,
    zoomFactor: 1.5,
    autoLoot: false,
    lootMode: "nearby",
    mobileMovement: false,
    menuKey: "ShiftRight",
    aimKey: "KeyB",
    stickyKey: "KeyN",
    holdAim: false
  });
  var STORAGE_KEY = "duality-reborn.config.v1";
  var ranges = { smooth: [0, 100], fov: [50, 400], smokeOpacity: [0, 100], treeOpacity: [0, 100], zoomFactor: [1, 3], espMaxDistance: [10, 500], espFontSize: [10, 18], espOpacity: [10, 100], espLineWidth: [0.5, 3] };
  var colors = /* @__PURE__ */ new Set(["espEnemyColor", "espAllyColor", "espUnknownColor", "espTargetColor"]);
  function normalizeConfig(saved) {
    const result = { ...DEFAULTS };
    if (!saved || typeof saved !== "object" || Array.isArray(saved)) return result;
    for (const [key, defaultValue] of Object.entries(DEFAULTS)) {
      const value = saved[key];
      if (typeof defaultValue === "boolean" && typeof value === "boolean") result[key] = value;
      if (colors.has(key) && colorValue(value)) result[key] = value.toLowerCase();
      if (ranges[key] && finite(value)) result[key] = clamp(value, ...ranges[key]);
      if (["menuKey", "aimKey", "stickyKey"].includes(key) && typeof value === "string" && /^(Key[A-Z]|Digit[0-9]|Shift(Left|Right)|Control(Left|Right)|Alt(Left|Right)|F([1-9]|1[0-2]))$/.test(value)) result[key] = value;
    }
    if (["nearby", "mobile"].includes(saved.lootMode)) result.lootMode = saved.lootMode;
    result.version = 1;
    return result;
  }
  __name(normalizeConfig, "normalizeConfig");
  function loadConfig(storage) {
    try {
      return normalizeConfig(JSON.parse(storage.getItem(STORAGE_KEY)));
    } catch {
      return { ...DEFAULTS };
    }
  }
  __name(loadConfig, "loadConfig");
  var CSS = `
:host{all:initial;position:fixed;inset:0;z-index:2147483646;pointer-events:none;color:#eaf6ff;font:13px system-ui,sans-serif}
*{box-sizing:border-box}button,input,select{font:inherit}select{max-width:200px;color:inherit;background:#17334c;border:1px solid #365168;padding:5px}button{cursor:pointer;color:inherit;background:#17334c;border:1px solid #365168;border-radius:5px;padding:7px 10px}button:hover{background:#23425b}button:disabled,input:disabled,select:disabled{cursor:not-allowed;opacity:.45}button:focus-visible,input:focus-visible,select:focus-visible{outline:2px solid #7dc5ff;outline-offset:2px}
canvas{position:fixed;inset:0;pointer-events:none}#ui{position:fixed;left:24px;top:24px;display:flex;width:720px;max-width:calc(100vw - 24px);max-height:85vh;border:1px solid #365168;border-radius:10px;background:#0c2335;pointer-events:auto;overflow:hidden}
.sidebar{width:180px;flex-shrink:0;padding:16px;background:#102a40;display:flex;flex-direction:column;gap:10px}.brand{font-weight:750;padding:6px 0 16px;cursor:move;touch-action:none;user-select:none}.version{font-size:11px;color:#91adc5;margin-top:6px}.nav{display:flex;flex-direction:column;gap:7px}.nav button{text-align:left;border-color:transparent;background:transparent}.nav button.active{background:#245377;border-color:#4076a0}.footer{margin-top:auto;display:flex;flex-direction:column;gap:8px}.content{min-width:0;flex:1;padding:20px;overflow-y:auto;overscroll-behavior:contain}h2{font-size:15px;margin:0 0 10px}fieldset{border:1px solid #29465d;border-radius:6px;margin:0 0 16px;padding:12px}legend{font-weight:650;padding:0 5px}.row{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:9px 0;min-height:24px}.row span{min-width:0}.row input[type=checkbox]{width:17px;height:17px;flex-shrink:0;accent-color:#65b7ef}.row input[type=color]{width:44px;height:26px;padding:1px;border:1px solid #365168;background:#17334c}.row input[type=range]{width:130px;accent-color:#65b7ef}.row output{width:36px;text-align:right}.hint{font-size:11px;color:#a3b9ca;line-height:1.6}#status{white-space:pre-wrap;word-break:break-word;font-size:11px;line-height:1.5;background:#081b2b;padding:10px;margin-bottom:14px;border:1px solid #29465d;border-radius:5px}p{line-height:1.6}a{color:#80c4ff}pre{white-space:pre-wrap;word-break:break-word;font-size:11px}.toolbar{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}[hidden]{display:none!important}@media(max-width:600px){#ui{left:12px;top:12px}.sidebar{width:122px;padding:10px}.content{padding:12px}.row{gap:6px}.row input[type=range]{width:85px}}
`;
  var GROUPS = {
    Main: [
      ["Aimbot", [
        ["aim", "Enabled", "aim"],
        ["smoothEnabled", "Use Smooth", "aim"],
        ["smooth", "Smooth", "aim"],
        ["knocked", "Target Knocked", "aim"],
        ["sticky", "Sticky Target", "aim"],
        ["showDot", "Aimbot Dot"],
        ["fov", "FOV"],
        ["showFov", "Show FOV Circle"],
        ["wallcheck", "Wallcheck", "wallcheck"],
        ["predict", "Prediction", "prediction"]
      ]],
      ["Melee Lock", [["melee", "Enabled", "mobile"]]],
      ["Auto Switch", [["autoSwitch", "Enabled (two guns)", "switch"]]],
      ["Semi Auto", [["semi", "Enabled", "semi"]]]
    ],
    Visuals: [
      ["X-Ray", [["xray", "Enabled", "visuals"], ["ceilings", "Remove Ceilings", "visuals"], ["smokeOpacity", "Smoke Opacity", "visuals"], ["treeOpacity", "Tree / Bush Opacity", "visuals"]]],
      ["Layer Spoofer", [[null, "Chưa port: cần kiểm chứng layer semantics"]]],
      ["ESP / Teams", [
        ["esp", "Enabled", "visuals"],
        ["espShowEnemies", "Show enemies", "visuals"],
        ["espShowAllies", "Show allies / squad", "visuals"],
        ["espShowUnknown", "Show unknown team", "visuals"],
        ["espShowDowned", "Show downed", "visuals"],
        ["espSameLayerOnly", "Same layer only", "visuals"],
        ["espMaxDistance", "Max range (world units)", "visuals"],
        [null, "ENEMY / ALLY / SQUAD / UNKNOWN theo teamInfo và groupInfo. Không mặc định unknown là địch."]
      ]],
      ["ESP / Display", [
        ["lines", "Player lines", "visuals"],
        ["espMarkers", "Player markers", "visuals"],
        ["espLabels", "Relation / status labels", "visuals"],
        ["nametags", "Player names", "visuals"],
        ["espDistance", "Distance (world units)", "visuals"],
        ["espWeapons", "Equipped weapon", "visuals"],
        ["espOffscreen", "Off-screen arrows (received entities only)", "visuals"],
        ["espHighlightTarget", "Highlight current enemy target", "visuals"],
        ["espLegend", "Color legend / counts", "visuals"],
        ["espFontSize", "Label size", "visuals"],
        ["espOpacity", "Overlay opacity", "visuals"],
        ["espLineWidth", "Line width", "visuals"]
      ]],
      ["ESP / Colors", [["espEnemyColor", "Enemy", "visuals"], ["espAllyColor", "Ally / squad", "visuals"], ["espUnknownColor", "Unknown", "visuals"], ["espTargetColor", "Current enemy target", "visuals"]]],
      ["Grenades", [["grenadeZones", "Nominal Explosion Radius", "grenadeZones"], [null, "Không phải vùng sát thương chắc chắn; chưa có fuse / trajectory"]]],
      ["Flashlights", [["ownFlashlight", "Own Range / Spread Preview", "prediction"], [null, "Others / Ricochet: chưa port"]]],
      ["Infinite Zoom", [["zoom", "Enabled (bounded 1–3×)", "zoom"], ["zoomFactor", "Zoom Out", "zoom"]]]
    ],
    Misc: [
      ["Map Highlights", [[null, "Chưa port: không hook Array.sort toàn trang"]]],
      ["Auto Loot", [["autoLoot", "Enabled", "sender"], ["lootMode", "Pickup mode", "sender"], [null, "Nearby: ammo / heal / boost / throwable; bỏ qua súng và gear. Mobile: cần Join mới, có cả mở cửa."]]],
      ["Mobile Movement", [["mobileMovement", "Enabled", "mobile"]]]
    ]
  };
  function createMenu(win, config, { onChange, retry, stop, diagnostics, onAimHold = /* @__PURE__ */ __name(() => {
  }, "onAimHold") }) {
    const doc = win.document, host = doc.createElement("div");
    host.id = "duality-reborn-host";
    const root = host.attachShadow({ mode: "open" });
    const el = /* @__PURE__ */ __name((tag, props = {}, ...children) => {
      const n = doc.createElement(tag);
      for (const [k, value] of Object.entries(props)) {
        if (k === "text") n.textContent = value;
        else if (k === "class") n.className = value;
        else n[k] = value;
      }
      children.forEach((c) => n.append(c));
      return n;
    }, "el");
    const style = el("style", { text: CSS });
    const canvas = el("canvas");
    canvas.setAttribute("aria-hidden", "true");
    const shell = el("section", { id: "ui" });
    shell.setAttribute("aria-label", "Duality Client Reborn");
    const brand = el("div", { class: "brand", text: "Duality Client" }, el("div", { class: "version", text: "Reborn 0.3.0 • readable debug" }));
    const nav = el("nav", { class: "nav" });
    nav.setAttribute("aria-label", "Menu tabs");
    const content = el("main", { class: "content" });
    const status = el("div", { id: "status", text: "Đang chờ Application…" });
    status.setAttribute("role", "status");
    const panel = el("div");
    const close = el("button", { text: "Close" });
    close.onclick = () => {
      shell.hidden = true;
    };
    const retryButton = el("button", { text: "Retry capture" });
    retryButton.onclick = retry;
    const stopButton = el("button", { text: "Stop / cleanup" });
    stopButton.onclick = stop;
    const sidebar = el("aside", { class: "sidebar" }, brand, nav, el("div", { class: "footer" }, close, retryButton, stopButton));
    content.append(status, panel);
    shell.append(sidebar, content);
    root.append(style, canvas, shell);
    (doc.body || doc.documentElement).append(host);
    let tab = "Main", caps = {}, dead = false, storageTimer = null, captureKey = null, keyTimeout = null;
    const listeners = new AbortController();
    const controller = win.AbortController ? new win.AbortController() : listeners;
    const signal = controller.signal;
    const persist = /* @__PURE__ */ __name(() => {
      win.clearTimeout(storageTimer);
      storageTimer = win.setTimeout(() => {
        try {
          win.localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
        } catch {
          status.textContent = "Không lưu được cấu hình; tiếp tục dùng trong bộ nhớ.";
        }
      }, 200);
    }, "persist");
    const set = /* @__PURE__ */ __name((key, value) => {
      config[key] = value;
      persist();
      onChange(key, value);
    }, "set");
    const cancelKey = /* @__PURE__ */ __name(() => {
      captureKey = null;
      win.clearTimeout(keyTimeout);
    }, "cancelKey");
    const row = /* @__PURE__ */ __name(([key, label, capability]) => {
      if (key === null) return el("div", { class: "hint", text: label });
      const title = el("span", { text: label }), labelEl = el("label", { class: "row" }, title);
      const input = key === "lootMode" ? el("select") : el("input", { type: colors.has(key) ? "color" : ranges[key] ? "range" : "checkbox" });
      if (key === "lootMode") {
        for (const [value, text] of [["nearby", "Nearby supplies (now)"], ["mobile", "Mobile loot / doors (next join)"]]) input.append(el("option", { value, text }));
        input.value = config.lootMode;
        input.onchange = () => set(key, input.value);
      }
      if (capability && !caps[capability]) {
        input.disabled = true;
        labelEl.title = `Đang chờ contract: ${capability}. Chưa xác nhận trên build này.`;
      }
      if (colors.has(key)) {
        input.value = config[key];
        input.onchange = () => {
          if (colorValue(input.value)) set(key, input.value.toLowerCase());
        };
        labelEl.append(input);
      } else if (key === "lootMode") {
        labelEl.append(input);
      } else if (ranges[key]) {
        [input.min, input.max] = ranges[key];
        input.step = key === "zoomFactor" ? 0.1 : key === "espLineWidth" ? 0.5 : 1;
        input.value = config[key];
        const output = el("output", { text: String(config[key]) });
        input.oninput = () => {
          const value = Number(input.value);
          set(key, value);
          output.textContent = String(value);
        };
        labelEl.append(input, output);
      } else {
        input.checked = config[key];
        input.onchange = () => set(key, input.checked);
        labelEl.append(input);
      }
      return labelEl;
    }, "row");
    const render = /* @__PURE__ */ __name(() => {
      if (dead) return;
      cancelKey();
      panel.replaceChildren();
      for (const button of nav.children) {
        button.classList.toggle("active", button.textContent === tab);
        button.setAttribute("aria-pressed", String(button.textContent === tab));
      }
      if (GROUPS[tab]) {
        for (const [name, rows] of GROUPS[tab]) panel.append(el("fieldset", {}, el("legend", { text: name }), ...rows.map(row)));
        if (tab === "Main") panel.append(el("p", { class: "hint", text: "Aim chỉ tác động khi giữ nút bắn và có đối thủ trong FOV quanh con trỏ. Trạng thái Aim ở trên cho biết vì sao đang chờ; wallcheck thiếu contract sẽ không âm thầm bị bỏ qua." }));
        if (tab === "Misc") panel.append(el("p", { class: "hint", text: "Nearby supplies hoạt động trong trận sau khi đủ contract; không tự đổi súng/gear và không giả nhặt thành công. Mobile mode dùng isMobile trong Join mới, có thể ảnh hưởng scope và tự mở cửa." }));
        return;
      }
      if (tab === "Keybinds") {
        for (const [key, label] of [["menuKey", "Toggle Menu"], ["aimKey", "Aimbot"], ["stickyKey", "Sticky Target"]]) {
          const button = el("button", { text: config[key] });
          button.onclick = () => {
            cancelKey();
            captureKey = { key, button };
            button.textContent = "Press key / Esc";
            keyTimeout = win.setTimeout(() => {
              cancelKey();
              render();
            }, 1e4);
          };
          panel.append(el("div", { class: "row" }, el("span", { text: label }), button));
        }
        panel.append(row(["holdAim", "Hold Aimbot Key"]));
        panel.append(el("p", { class: "hint", text: "Aimbot vẫn chỉ tác động khi đang giữ nút bắn. Phím tắt không chạy khi đang nhập văn bản. Esc hủy gán phím; focus/blur giải phóng hold." }));
        return;
      }
      panel.append(
        el("h2", { text: "Controls & Information" }),
        el("p", { text: "Bản viết lại độc lập. Menu giữ Main / Visuals / Misc / Keybinds / Help; không tải font, ảnh hay thư viện UI từ bên ngoài." }),
        el("p", { class: "hint", text: "ESP: màu + nhãn địch/ta/unknown; nét đứt cho layer khác / downed / unknown. Không suy đoán HP/armor của đối thủ. Layer Spoofer, Map Highlights và grenade trajectory vẫn chưa port. Chỉ hiển thị dữ liệu client nhận được. Không bảo đảm tương thích mọi update hay tránh phát hiện. Những mục chưa port được ghi rõ, không giả vờ đang hoạt động." })
      );
      const pre = el("pre", { text: JSON.stringify(diagnostics(), null, 2) });
      const refresh = el("button", { text: "Refresh diagnostics" });
      refresh.onclick = () => {
        pre.textContent = JSON.stringify(diagnostics(), null, 2);
      };
      const copy = el("button", { text: "Copy diagnostics" });
      copy.onclick = async () => {
        const text = JSON.stringify(diagnostics(), null, 2);
        pre.textContent = text;
        try {
          if (!win.navigator.clipboard?.writeText) throw new Error("Clipboard unavailable");
          await win.navigator.clipboard.writeText(text);
          if (!dead && copy.isConnected) copy.textContent = "Copied";
        } catch {
          if (dead || !copy.isConnected) return;
          const field = el("textarea", { value: text, readOnly: true, rows: 10 });
          field.setAttribute("aria-label", "Diagnostics JSON — Ctrl+C to copy");
          field.style.width = "100%";
          pre.replaceChildren(field);
          field.focus();
          field.select();
          copy.textContent = "Nhấn Ctrl+C để copy JSON";
        }
      };
      const reset2 = el("button", { text: "Reset config" });
      reset2.onclick = () => {
        Object.assign(config, DEFAULTS);
        persist();
        onChange("reset");
        render();
      };
      panel.append(el("div", { class: "toolbar" }, refresh, copy, reset2), pre);
    }, "render");
    for (const name of ["Main", "Visuals", "Misc", "Keybinds", "Help"]) {
      const button = el("button", { text: name });
      button.onclick = () => {
        tab = name;
        render();
      };
      nav.append(button);
    }
    const typing = /* @__PURE__ */ __name((event) => event.composedPath().some((n) => ["INPUT", "TEXTAREA", "SELECT"].includes(n.tagName) || n.isContentEditable), "typing");
    let holdPrevious = null;
    const releaseHold = /* @__PURE__ */ __name(() => {
      if (holdPrevious !== null) {
        config.aim = holdPrevious;
        holdPrevious = null;
        onAimHold(false);
        onChange("aim", config.aim);
        render();
      }
    }, "releaseHold");
    win.addEventListener("keydown", (event) => {
      if (captureKey) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (event.code !== "Escape") {
          const candidate = normalizeConfig({ ...config, [captureKey.key]: event.code });
          set(captureKey.key, candidate[captureKey.key]);
        }
        cancelKey();
        render();
        return;
      }
      if (event.repeat || typing(event)) return;
      if (event.code === config.menuKey) {
        shell.hidden = !shell.hidden;
        event.preventDefault();
      }
      if (event.code === config.aimKey) {
        if (config.holdAim) {
          if (holdPrevious === null) holdPrevious = config.aim;
          config.aim = true;
          onAimHold(true);
          onChange("aim", true);
        } else set("aim", !config.aim);
        render();
      }
      if (event.code === config.stickyKey) {
        set("sticky", !config.sticky);
        render();
      }
    }, { capture: true, signal });
    win.addEventListener("keyup", (event) => {
      if (event.code === config.aimKey) releaseHold();
    }, { signal });
    win.addEventListener("blur", () => {
      releaseHold();
      cancelKey();
    }, { signal });
    doc.addEventListener("visibilitychange", () => {
      if (doc.hidden) releaseHold();
    }, { signal });
    let drag = null;
    brand.addEventListener("pointerdown", (event) => {
      if (event.button !== 0) return;
      const rect = shell.getBoundingClientRect();
      drag = { dx: event.clientX - rect.left, dy: event.clientY - rect.top };
      brand.setPointerCapture?.(event.pointerId);
      event.preventDefault();
    }, { signal });
    brand.addEventListener("pointermove", (event) => {
      if (!drag) return;
      shell.style.left = `${clamp(event.clientX - drag.dx, 0, Math.max(0, win.innerWidth - shell.offsetWidth))}px`;
      shell.style.top = `${clamp(event.clientY - drag.dy, 0, Math.max(0, win.innerHeight - 60))}px`;
    }, { signal });
    for (const name of ["pointerup", "pointercancel", "lostpointercapture"]) brand.addEventListener(name, () => {
      drag = null;
    }, { signal });
    render();
    return {
      host,
      root,
      canvas,
      render,
      status(text) {
        if (!dead && status.textContent !== text) status.textContent = text;
      },
      capabilities(value) {
        if (JSON.stringify(caps) !== JSON.stringify(value)) {
          caps = { ...value };
          render();
        }
      },
      dispose() {
        if (dead) return;
        dead = true;
        releaseHold();
        controller.abort();
        win.clearTimeout(storageTimer);
        cancelKey();
        try {
          win.localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
        } catch {
        }
        host.remove();
      }
    };
  }
  __name(createMenu, "createMenu");

  // src/main.mjs
  function start(win) {
    const key = Symbol.for("duality.reborn.controller.v1");
    win[key]?.dispose?.();
    const bag = new Disposables();
    let config;
    try {
      config = loadConfig(win.localStorage);
    } catch {
      config = loadConfig(null);
    }
    let menu = null, engine = null, defs = null, cancelCapture = null, alive = true;
    let status = "Đang chờ Application…", lastWarning = "", captured = false, captureState = "waiting";
    const startedAt = win.performance.now();
    win.console?.info?.("[Duality Reborn 0.3.0] Script đã chạy. Nếu không có menu, gửi dòng lỗi Console sau thông báo này.");
    const report = /* @__PURE__ */ __name((level, message) => {
      if (!alive) return;
      if (level === "error" || level === "warning") {
        lastWarning = message;
        win.console?.warn?.("[Duality Reborn]", message);
      }
      status = message;
    }, "report");
    const diagnostics = /* @__PURE__ */ __name(() => ({
      version: "0.3.0",
      captured,
      captureState,
      status,
      lastWarning,
      menuMounted: !!menu?.host.isConnected,
      documentReadyState: win.document.readyState,
      definitionsCaptured: !!defs,
      elapsedMs: Math.round(win.performance.now() - startedAt),
      ...engine?.diagnostics() || {}
    }), "diagnostics");
    const controller = {
      diagnostics,
      retry() {
        if (!alive) return;
        cancelCapture?.();
        engine?.dispose();
        engine = null;
        captured = false;
        captureState = "waiting";
        menu?.capabilities({});
        status = "Capture có timeout 15 giây. Nếu không bắt được, reload với userscript bật từ document-start.";
        cancelCapture = captureApplication(win, (app) => {
          if (!alive) return;
          captured = true;
          captureState = "captured";
          try {
            engine = new Features(win, app, config, report, defs);
            if (menu) engine.attachCanvas(menu.canvas);
            status = "Đã bắt Application; chờ trạng thái trận và contract.";
          } catch (e) {
            engine?.dispose();
            engine = null;
            captureState = "error";
            report("error", `Không khởi tạo được: ${e.message}`);
          }
        }, { timeout: 15e3, onTimeout: /* @__PURE__ */ __name(() => {
          captureState = "timeout";
          report("warning", "Không bắt được Application trong 15 giây; hook đã gỡ. Có thể sai page-world, lỡ bootstrap hoặc contract không khớp. Gửi diagnostics; chưa xác định nguyên nhân.");
        }, "onTimeout") });
      },
      dispose() {
        if (!alive) return;
        alive = false;
        cancelCapture?.();
        engine?.dispose();
        menu?.dispose();
        bag.clear();
        if (win[key] === controller) delete win[key];
      }
    };
    win[key] = controller;
    bag.add(captureDefinitions(win, (value) => {
      defs = value;
      if (engine) {
        engine.definitions = defs;
        engine.lastMap = -Infinity;
      }
    }));
    const makeMenu = /* @__PURE__ */ __name(() => {
      if (!alive || menu) return;
      menu = createMenu(win, config, {
        onChange: /* @__PURE__ */ __name((key2) => {
          engine?.restoreInput();
          if (engine) {
            engine.overrides.clear();
            engine.lastMap = -Infinity;
            engine.stickyId = null;
          }
          if (key2 === "autoLoot" || key2 === "lootMode") status = config.lootMode === "mobile" ? "Mobile loot: cần Join mới. Bật/tắt giữa trận không đổi mobile mode server đã nhận." : "Nearby supplies: dùng input Loot trong trận khi đủ contract; không tự đổi súng/gear.";
        }, "onChange"),
        retry: /* @__PURE__ */ __name(() => controller.retry(), "retry"),
        stop: /* @__PURE__ */ __name(() => controller.dispose(), "stop"),
        diagnostics
      });
      if (engine) engine.attachCanvas(menu.canvas);
    }, "makeMenu");
    if (win.document.body) makeMenu();
    else {
      win.document.addEventListener("DOMContentLoaded", makeMenu, { once: true });
      bag.add(() => win.document.removeEventListener("DOMContentLoaded", makeMenu));
    }
    const timer = win.setInterval(() => {
      if (!menu) return;
      menu.capabilities(engine?.capabilities || {});
      const d = diagnostics();
      menu.status(`${status}
Aim: ${d.stats?.aimState ?? "chưa mapping"} • Loot: ${d.autoLoot?.state ?? "chưa mapping"}
ESP: ${d.stats?.esp?.state ?? "chưa mapping"}${d.stats?.esp ? ` • địch ${d.stats.esp.enemy} / ta ${d.stats.esp.ally} / chưa rõ ${d.stats.esp.unknown}` : ""}
Protocol: ${d.protocol ?? "chưa quan sát Join"} • ${d.initialized ? "trong trận" : "chờ trận"}
${d.stats ? `Discovery: ${d.stats.mappingRuns} • visual tick: ${d.stats.featureMs.toFixed(2)} ms (không phải FPS benchmark)` : ""}${d.missingContracts?.length ? `
Thiếu contract: ${d.missingContracts.join(", ")}` : ""}${lastWarning ? `
Chú ý: ${lastWarning}` : ""}`);
    }, 1e3);
    bag.add(() => win.clearInterval(timer));
    const onPageHide = /* @__PURE__ */ __name(() => controller.dispose(), "onPageHide");
    win.addEventListener("pagehide", onPageHide, { once: true });
    bag.add(() => win.removeEventListener("pagehide", onPageHide));
    controller.retry();
    return controller;
  }
  __name(start, "start");
  if (typeof window !== "undefined") start(window);
})();
