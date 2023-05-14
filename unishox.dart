/* Copyright (C) 2020-2022 Siara Logics (cc) Copyright (C) 2022 exxjob
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
 * file except in compliance with the License. You may obtain a copy of the License at
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the License for the specific language
 * governing permissions and limitations under the License.
 *
 * @author Arundale Ramanathan, exxjob
 * @file unishox2.dart
 * @brief Dart implementation for Unishox2 compression of unicode strings
 */

// ignore_for_file: non_constant_identifier_names, constant_identifier_names
import 'dart:typed_data';

final USX_HCODES_DFLT = Uint8List.fromList([0x00, 0x40, 0x80, 0xC0, 0xE0]);
var USX_HCODE_LENS_DFLT = Uint8List.fromList([2, 2, 2, 3, 3]);
var USX_HCODES_ALPHA_NUM_SYM_ONLY = Uint8List.fromList([0x00, 0x80, 0xC0, 0x00, 0x00]);
var USX_HCODE_LENS_ALPHA_NUM_SYM_ONLY = Uint8List.fromList([1, 2, 2, 0, 0]);
var USX_FREQ_SEQ_DFLT = ["\": \"", "\": ", "</", "=\"", "\":\"", "://"];
var USX_TEMPLATES = ["tfff-of-tfTtf:rf:rf.fffZ", "tfff-of-tf", "(fff) fff-ffff", "tf:rf:rf", 0];

const USX_ALPHA = 0; const USX_SYM = 1; const USX_NUM = 2; const USX_DICT = 3; const USX_DELTA = 4;

final List<Uint8List> usx_sets = ["\u0000 etaoinsrlcdhupmbgwfyvkqjxz".codeUnits as Uint8List, "\"{}_<>:\n\u0000[]\\;'\t@*&?!^|\r~`\u0000\u0000\u0000".codeUnits as Uint8List, "\u0000,.01925-/34678() =+\$%#\u0000\u0000\u0000\u0000\u0000".codeUnits as Uint8List,];

Uint8List usx_code_94 = Uint8List(94)..fillRange(0,94,0);

Uint8List usx_vcodes  = Uint8List.fromList([0x00, 0x40, 0x60, 0x80, 0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xD8, 0xE0, 0xE4, 0xE8, 0xEC, 0xEE, 0xF0, 0xF2, 0xF4, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF]);
Uint8List usx_vcode_lens = Uint8List.fromList([2, 3, 3, 4, 4, 4, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]);

Uint8List usx_freq_codes = Uint8List.fromList([(1 << 5) + 25, (1 << 5) + 26, (1 << 5) + 27, (2 << 5) + 23, (2 << 5) + 24, (2 << 5) + 25]);

var NICE_LEN = 5;

const RPT_CODE = ((2 << 5) + 26);
const TERM_CODE = ((2 << 5) + 27);
const LF_CODE = ((1 << 5) + 7);
const CRLF_CODE = ((1 << 5) + 8);
const CR_CODE = ((1 << 5) + 22);
const TAB_CODE = ((1 << 5) + 14);
const NUM_SPC_CODE = ((2 << 5) + 17);

const UNI_STATE_SPL_CODE = 0xF8;
const UNI_STATE_SPL_CODE_LEN = 5;
const UNI_STATE_SW_CODE = 0x80;
const UNI_STATE_SW_CODE_LEN = 2;

const SW_CODE = 0;
const SW_CODE_LEN = 2;
const TERM_BYTE_PRESET_1 = 0;
const TERM_BYTE_PRESET_1_LEN_LOWER = 6;
const TERM_BYTE_PRESET_1_LEN_UPPER = 4;

const USX_OFFSET_94 = 33;

bool need_full_term_codes = false;

bool is_inited = false; void init_coder() {
  if (is_inited) { return; }
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 28; j++) {
      var c = usx_sets[i][j];
      if (c != 0 && c > 32) {
        usx_code_94[c - USX_OFFSET_94] = (i << 5) + j;
        if (c >= 97 && c <= 122) { usx_code_94[c - USX_OFFSET_94 - (97 - 65)] = (i << 5) + j; }
      }
    }
  } is_inited = true;
}

Uint8List usx_mask = Uint8List.fromList([0x80, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE, 0xFF]);
int append_bits(out, int olen, int ol, code, int clen) {
  while (clen > 0) {
    var cur_bit = ol % 8;
    var blen = clen;
    var a_byte = code & usx_mask[blen - 1];
    a_byte >>= cur_bit;
    if (blen + cur_bit > 8) { blen = (8 - cur_bit); }
    var oidx = ol / 8;
    if (oidx < 0 || olen <= oidx) { return -1; }
    if (cur_bit == 0) { out[ol >> 3] = a_byte; }
    else { out[ol >> 3] |= a_byte; }
    code <<= blen;
    ol += blen;
    clen -= blen;
  }
  return ol;
}

int append_switch_code(out, int olen, int ol, state) {
  if (state == USX_DELTA) {
    ol = append_bits(out, olen, ol, UNI_STATE_SPL_CODE, UNI_STATE_SPL_CODE_LEN);
    ol = append_bits(out, olen, ol, UNI_STATE_SW_CODE, UNI_STATE_SW_CODE_LEN);
  }
  else { ol = append_bits(out, olen, ol, SW_CODE, SW_CODE_LEN); }
  return ol;
}

append_code(out, int olen, int ol, code, state, usx_hcodes, usx_hcode_lens) {
  var hcode = code >> 5;
  var vcode = code & 0x1F;
  if (usx_hcode_lens[hcode] == 0 && hcode != USX_ALPHA) {
    return (ol, state);
  }
  switch (hcode) {
    case USX_ALPHA:
      if (state != USX_ALPHA) {
        ol = append_switch_code(out, olen, ol, state);
        ol = append_bits(out, olen, ol, usx_hcodes[USX_ALPHA], usx_hcode_lens[USX_ALPHA]);
        state = USX_ALPHA;
      }
      break;
    case USX_SYM:
      ol = append_switch_code(out, olen, ol, state);
      ol = append_bits(out, olen, ol, usx_hcodes[USX_SYM], usx_hcode_lens[USX_SYM]);
      break;
    case USX_NUM:
      if (state != USX_NUM) {
        ol = append_switch_code(out, olen, ol, state);
        ol = append_bits(out, olen, ol, usx_hcodes[USX_NUM], usx_hcode_lens[USX_NUM]);
        if (usx_sets[hcode][vcode] >= 48 && usx_sets[hcode][vcode] <= 57) { state = USX_NUM; }
      }
  }
  return (append_bits(out, olen, ol, usx_vcodes[vcode], usx_vcode_lens[vcode]), state);
}

final count_bit_lens = Uint8List.fromList([2, 4, 7, 11, 16]);
const count_adder = [4, 20, 148, 2196, 67732];
final count_codes = Uint8List.fromList([0x01, 0x82, 0xC3, 0xE4, 0xF4]);
int encodeCount(out, int olen, int ol, int count) {
  for (var i = 0; i < 5; i++) {
    if (count < count_adder[i]) {
      ol = append_bits(out, olen, ol, (count_codes[i] & 0xF8), count_codes[i] & 0x07);
      var count16 = (count - (i > 0 ? count_adder[i - 1] : 0)) << (16 - count_bit_lens[i]);
      if (count_bit_lens[i] > 8) {
        ol = append_bits(out, olen, ol, count16 >> 8, 8);
        ol = append_bits(out, olen, ol, count16 & 0xFF, count_bit_lens[i] - 8);
      }
      else { ol = append_bits(out, olen, ol, count16 >> 8, count_bit_lens[i]); }
      return ol;
    }
  }
  return ol;
}


final uni_bit_len = Uint8List.fromList([6, 12, 14, 16, 21]);
const uni_adder = [0, 64, 4160, 20544, 86080];

int encodeUnicode(out, int olen, int ol, code, prev_code) {
  final codes = Uint8List.fromList([0x01, 0x82, 0xC3, 0xE4, 0xF5, 0xFD]);
  var till = 0;
  var diff = code - prev_code;
  if (diff < 0) { diff = -diff; }
  for (var i = 0; i < 5; i++) {
    till += (1 << uni_bit_len[i]);
    if (diff < till) {
      ol = append_bits(out, olen, ol, (codes[i] & 0xF8), codes[i] & 0x07);
      ol = append_bits(out, olen, ol, prev_code > code ? 0x80 : 0, 1);
      var val = diff - uni_adder[i];
      switch (uni_bit_len[i]){
        case > 16:
          val <<= (24 - uni_bit_len[i]);
          ol = append_bits(out, olen, ol, val >> 16, 8);
          ol = append_bits(out, olen, ol, (val >> 8) & 0xFF, 8);
          ol = append_bits(out, olen, ol, val & 0xFF, uni_bit_len[i] - 16);
          break;
        case > 8:
          val <<= (16 - uni_bit_len[i]);
          ol = append_bits(out, olen, ol, val >> 8, 8);
          ol = append_bits(out, olen, ol, val & 0xFF, uni_bit_len[i] - 8);
          break;
        default:
          val <<= (8 - uni_bit_len[i]);
          ol = append_bits(out, olen, ol, val & 0xFF, uni_bit_len[i]);

      }
      return ol;
    }
  }
  return ol;
}


readUTF8(input, int len, int l){
  var ret = 0;
  if (input is String) {
    ret = input.codeUnitAt(l);
    return (ret, ret == input.codeUnitAt(l) ? 1 : 2);
  }
  int utf8len = 0;
  if (l < (len - 1) && (input[l] & 0xE0) == 0xC0 && (input[l + 1] & 0xC0) == 0x80) {
    utf8len = 2;
    ret = (input[l] & 0x1F);
    ret <<= 6;
    ret += ((input[l + 1] as int) & 0x3F);
    if (ret < 0x80) { ret = 0; }
  }
  else if (l < (len - 2) && (input[l] & 0xF0) == 0xE0 && (input[l + 1] & 0xC0) == 0x80 && (input[l + 2] & 0xC0) == 0x80) {
    utf8len = 3;
    ret = (input[l] & 0x0F);
    ret <<= 6;
    ret += ((input[l + 1] as int) & 0x3F);
    ret <<= 6;
    ret += ((input[l + 2] as int) & 0x3F);
    if (ret < 0x0800) { ret = 0; }
  }
  else if (l < (len - 3) && (input[l] & 0xF8) == 0xF0 && (input[l + 1] & 0xC0) == 0x80 && (input[l + 2] & 0xC0) == 0x80 && (input[l + 3] & 0xC0) == 0x80) {
    utf8len = 4;
    ret = (input[l] & 0x07);
    ret <<= 6;
    ret += ((input[l + 1] as int) & 0x3F);
    ret <<= 6;
    ret += ((input[l + 2] as int) & 0x3F);
    ret <<= 6;
    ret += ((input[l + 3] as int) & 0x3F);
    if (ret < 0x10000) { ret = 0; }
  }
  return (ret, utf8len);
}

(int, int) matchOccurrence(input, int len, int l, out, int olen, int ol, state, usx_hcodes, usx_hcode_lens) {
  int j, k;
  var longest_dist = 0;
  var longest_len = 0;
  for (j = l - NICE_LEN; j >= 0; j--) {
    for (k = l; k < len && j + k - l < l; k++) {
      if (input[k] != input[j + k - l]){ break; }  // todo check break
    }
    while ((input[k] >> 6) == 2) { k--; }
    if (k - l > NICE_LEN - 1) {
      var match_len = k - l - NICE_LEN;
      var match_dist = l - j - NICE_LEN + 1;
      if (match_len > longest_len) {
        longest_len = match_len;
        longest_dist = match_dist;
      }
    }
  }
  if (longest_len > 0) {
    ol = append_switch_code(out, olen, ol, state);
    ol = append_bits(out, olen, ol, usx_hcodes[USX_DICT], usx_hcode_lens[USX_DICT]);
    ol = encodeCount(out, olen, ol, longest_len);
    ol = encodeCount(out, olen, ol, longest_dist);
    l += (longest_len + NICE_LEN);
    l--;
    return (l, ol);
  }
  return (-l, ol);
}


(int, int) matchLine(input, int len, int l, out, int olen, int ol, prev_lines, int prev_lines_idx, state, usx_hcodes, usx_hcode_lens) {
  var last_ol = ol;
  var last_len = 0;
  var last_dist = 0;
  var last_ctx = 0;
  var line_ctr = 0;
  var j = 0;
  do {
    int k;
    var prev_line = prev_lines[prev_lines_idx - line_ctr];
    var line_len = prev_line.length;
    var limit = (line_ctr == 0 ? l : line_len);
    for (; j < limit; j++) {
      int i = l; for (k = j; k < line_len && k < limit && i < len; k++, i++) {
        if (prev_line[k] != input[i]) { break; }  // todo check
      }
      while ((prev_line[k] >> 6) == 2) { k--; }
      if ((k - j) >= NICE_LEN) {
        if (last_len > 0) {
          if (j > last_dist) { continue; }  // todo check
          ol = last_ol;
        }
        last_len = k - j;
        last_dist = j;
        last_ctx = line_ctr;
        ol = append_switch_code(out, olen, ol, state);
        ol = append_bits(out, olen, ol, usx_hcodes[USX_DICT], usx_hcode_lens[USX_DICT]);
        ol = encodeCount(out, olen, ol, last_len - NICE_LEN);
        ol = encodeCount(out, olen, ol, last_dist);
        ol = encodeCount(out, olen, ol, last_ctx);
        j += last_len;
      }
    }
  } while (line_ctr++ < prev_lines_idx);
  if (last_len > 0) {
    l += last_len - 1;
    return (l, ol);
  }
  return (-l, ol);
}

int getBaseCode(ch){
  switch (ch){
    case >= 48 && <= 57: return (ch - 48) << 4;
    case >= 65 && <= 70: return (ch - 65 + 10) << 4;
    case >= 97 && <= 102: return (ch - 97 + 10) << 4;
    default: return 0;
  }
}

const USX_NIB_NUM = 0;
const USX_NIB_HEX_LOWER = 1;
const USX_NIB_HEX_UPPER = 2;
const USX_NIB_NOT = 3;
int getNibbleType(ch){
  switch (ch) {
    case >= 48 && <= 57: return USX_NIB_NUM;
    case >= 97 && <= 102: return USX_NIB_HEX_LOWER;
    case >= 65 && <= 70: return USX_NIB_HEX_UPPER;
    default: return USX_NIB_NOT;
  }
}

int append_nibble_escape(out, int olen, int ol, state, usx_hcodes, usx_hcode_lens) {
  ol = append_switch_code(out, olen, ol, state);
  ol = append_bits(out, olen, ol, usx_hcodes[USX_NUM], usx_hcode_lens[USX_NUM]);
  ol = append_bits(out, olen, ol, 0, 2);
  return ol;
}

int append_final_bits(out, int olen, int ol, state, is_all_upper, usx_hcodes, usx_hcode_lens) {
  if (usx_hcode_lens[USX_ALPHA]) {
    if (USX_NUM != state) {
      ol = append_switch_code(out, olen, ol, state);
      ol = append_bits(out, olen, ol, usx_hcodes[USX_NUM], usx_hcode_lens[USX_NUM]);
    }
    ol = append_bits(out, olen, ol, usx_vcodes[TERM_CODE & 0x1F], usx_vcode_lens[TERM_CODE & 0x1F]);
  }
  else { ol = append_bits(out, olen, ol, TERM_BYTE_PRESET_1, is_all_upper ? TERM_BYTE_PRESET_1_LEN_UPPER : TERM_BYTE_PRESET_1_LEN_LOWER); }
  ol = append_bits(out, olen, ol, (ol == 0 || out[(ol-1)/8] << ((ol-1)&7) >= 0) ? 0 : 0xFF, (8 - ol % 8) & 7);
  return ol;
}

bool compare_arr(arr1, arr2, is_str) {
  if (is_str) { return arr1 == arr2; }
  else {
    if (arr1.length != arr2.length) { return false; }
    for (var i = 0; i < arr2.length; i++) {
      if (arr1.codeUnitAt(i) != arr2[i]) { return false; }
    }
  }
  return true;
}


final usx_spl_code = Uint8List.fromList([0, 0xE0, 0xC0, 0xF0]);
final usx_spl_code_len = Uint8List.fromList([1, 4, 3, 4]);

unishox2_compress(input, int len, out, {Uint8List? usx_hcodes, Uint8List? usx_hcode_lens, usx_freq_seq, usx_templates}){
  usx_hcodes ??= USX_HCODES_DFLT;
  usx_hcode_lens ??= USX_HCODE_LENS_DFLT;
  usx_freq_seq ??= USX_FREQ_SEQ_DFLT;
  usx_templates ??= USX_TEMPLATES;

  int state;
  int l, ll;
  var c_in, c_next;
  int prev_uni;
  bool is_upper, is_all_upper;
  List<String>? prev_lines_arr;
  int prev_lines_idx;

  prev_lines_idx = len;  // todo check
  if (input is List<String>){
    prev_lines_arr = input;
    input = prev_lines_arr[prev_lines_idx];
    len = input.length;
  }

  var olen = out.length;

  var is_str = (input is String);

  init_coder();
  prev_uni = 0;
  state = USX_ALPHA;
  is_all_upper = false;
  int ol = append_bits(out, olen, 0, 0x80, 1);
  for (l=0; l<len; l++) {

    if (usx_hcode_lens[USX_DICT] > 0 && l < (len - NICE_LEN + 1)) {
      if (prev_lines_arr != null) {
        (l, ol) = matchLine(input, len, l, out, olen, ol, prev_lines_arr, prev_lines_idx, state, usx_hcodes, usx_hcode_lens);
        if (l > 0) { continue; }  // todo check
        else if (l < 0 && ol < 0) { return olen + 1; }
        l = -l;
      }
      else {
        (l, ol) = matchOccurrence(input, len, l, out, olen, ol, state, usx_hcodes, usx_hcode_lens);
        if (l > 0) { continue; }  // todo check
        else if (l < 0 && ol < 0) { return olen + 1; }
        l = -l;
      }
    }

    c_in = input[l];
    if (l > 0 && len > 4 && l < len - 4 && usx_hcode_lens[USX_NUM] > 0 && c_in <= (is_str ? '~' : 126)) {
      if (c_in == input[l - 1] && c_in == input[l + 1] && c_in == input[l + 2] && c_in == input[l + 3]) {
        var rpt_count = l + 4;
        while (rpt_count < len && input[rpt_count] == c_in) {rpt_count++;}
        rpt_count -= l;
        (ol, state) = append_code(out, olen, ol, RPT_CODE, state, usx_hcodes, usx_hcode_lens);
        ol = encodeCount(out, olen, ol, rpt_count - 4);
        l += rpt_count - 1;
        continue;  // todo check
      }
    }

    if (l <= (len - 36) && usx_hcode_lens[USX_NUM] > 0) {
      var hyp_code = (is_str ? '-' : 45);
      var hex_type = USX_NIB_NUM;
      if (input[l + 8] == hyp_code && input[l + 13] == hyp_code && input[l + 18] == hyp_code && input[l + 23] == hyp_code) {
        var uid_pos = l;
        for (; uid_pos < l + 36; uid_pos++) {
          var c_uid = (is_str ? input.codeUnitAt(uid_pos) : input[uid_pos]);
          if (c_uid == 45 && (uid_pos == 8 || uid_pos == 13 || uid_pos == 18 || uid_pos == 23)) { continue; }  // todo check
          var nib_type = getNibbleType(c_uid);
          if (nib_type == USX_NIB_NOT) { break; }  // todo check
          if (nib_type != USX_NIB_NUM) {
            if (hex_type != USX_NIB_NUM && hex_type != nib_type) { break; }  // todo check
            hex_type = nib_type;
          }
        }
        if (uid_pos == l + 36) {
          ol = append_nibble_escape(out, olen, ol, state, usx_hcodes, usx_hcode_lens);
          ol = append_bits(out, olen, ol, (hex_type == USX_NIB_HEX_LOWER ? 0xC0 : 0xF0), (hex_type == USX_NIB_HEX_LOWER ? 3 : 5));
          for (uid_pos = l; uid_pos < l + 36; uid_pos++) {
            var c_uid = (is_str ? input.codeUnitAt(uid_pos) : input[uid_pos]);
            if (c_uid != 45){ ol = append_bits(out, olen, ol, getBaseCode(c_uid), 4); }
          }
          l += 35;
          continue;  // todo check
        }
      }
    }

    if (l < (len - 5) && usx_hcode_lens[USX_NUM] > 0) {
      var hex_type = USX_NIB_NUM;
      var hex_len = 0;
      do {
        var c_uid = (is_str ? input.codeUnitAt(l + hex_len) : input[l + hex_len]);
        var nib_type = getNibbleType(c_uid);
        if (nib_type == USX_NIB_NOT){ break; }  // todo check
        if (nib_type != USX_NIB_NUM) {
          if (hex_type != USX_NIB_NUM && hex_type != nib_type){ break; }  // todo check
          hex_type = nib_type;
        }
        hex_len++;
      } while (l + hex_len < len);
      if (hex_len > 10 && hex_type == USX_NIB_NUM) { hex_type = USX_NIB_HEX_LOWER; }
      if ((hex_type == USX_NIB_HEX_LOWER || hex_type == USX_NIB_HEX_UPPER) && hex_len > 3) {
        ol = append_nibble_escape(out, olen, ol, state, usx_hcodes, usx_hcode_lens);
        ol = append_bits(out, olen, ol, (hex_type == USX_NIB_HEX_LOWER ? 0x80 : 0xE0), (hex_type == USX_NIB_HEX_LOWER ? 2 : 4));
        ol = encodeCount(out, olen, ol, hex_len);
        do {
          var c_uid = (is_str ? input.codeUnitAt(l) : input[l]);
          ol = append_bits(out, olen, ol, getBaseCode(c_uid), 4);
          l++;
        } while (--hex_len > 0);
        l--;
        continue;  // todo check
      }
    }

    if (usx_templates != null) {
      int i;
      for (i = 0; i < 5; i++) {
        if (usx_templates[i] is String) {
          var rem = usx_templates[i].length;
          var j = 0;
          for (; j < rem && l + j < len; j++) {
            var c_t = usx_templates[i][j];
            c_in = (is_str ? input.codeUnitAt(l + j) : input[l + j]);
            switch(c_t) {
              case 'f' || 'F':
                if (getNibbleType(c_in) != (c_t == 'f' ? USX_NIB_HEX_LOWER : USX_NIB_HEX_UPPER) && getNibbleType(c_in) != USX_NIB_NUM) { break; }  // todo check
                break;
              case 'r' || 't' || 'o':
                if (c_in < 48 || c_in > (c_t == 'r' ? 55 : (c_t == 't' ? 51 : 49))){ break; } // todo check
                break;
              default: if (c_t.codeUnitAt(0) != c_in){ break; }  // todo check
            }
          }
          if ((j / rem) > 0.66) {
            rem = rem - j;
            ol = append_nibble_escape(out, olen, ol, state, usx_hcodes, usx_hcode_lens);
            ol = append_bits(out, olen, ol, 0, 1);
            ol = append_bits(out, olen, ol, (count_codes[i] & 0xF8), count_codes[i] & 0x07);
            ol = encodeCount(out, olen, ol, rem);
            for (var k = 0; k < j; k++) {
              var c_t = usx_templates[i][k];
              c_in = (is_str ? input.codeUnitAt(l + k) : input[l + k]);
              if (c_t == 'f' || c_t == 'F') { ol = append_bits(out, olen, ol, getBaseCode(c_in), 4); }
              else if (c_t == 'r' || c_t == 't' || c_t == 'o') {
                c_t = (c_t == 'r' ? 3 : (c_t == 't' ? 2 : 1));
                ol = append_bits(out, olen, ol, (c_in - 48) << (8 - c_t), c_t);
              }
            }
            l += j - 1;
            break;  // todo check
          }
        }
      }
      if (i < 5){ continue; }  // todo check
    }

    if (usx_freq_seq != null) {
      int i;
      for (i = 0; i < 6; i++) {
        int seq_len = usx_freq_seq[i].length;
        if (len - seq_len >= 0 && l <= len - seq_len){
          if (usx_hcode_lens[usx_freq_codes[i] >> 5] as bool && compare_arr(usx_freq_seq[i].slice(0, seq_len), input.slice(l, l + seq_len), is_str)) {  // todo check
            (ol, state) = append_code(out, olen, ol, usx_freq_codes[i], state, usx_hcodes, usx_hcode_lens);
            l += seq_len - 1;
            break;  // todo check
          }
        }
      }
      if (i < 6){ continue; }  // todo check
    }
    c_in = (is_str ? input.codeUnitAt(l) : input[l]);

    is_upper = false;
    if (c_in >= 65 && c_in <= 90){ is_upper = true; }
    else {
      if (is_all_upper) {
        is_all_upper = false;
        ol = append_switch_code(out, olen, ol, state);
        ol = append_bits(out, olen, ol, usx_hcodes[USX_ALPHA], usx_hcode_lens[USX_ALPHA]);
        state = USX_ALPHA;
      }
    }
    if (is_upper && !is_all_upper) {
      if (state == USX_NUM) {
        ol = append_switch_code(out, olen, ol, state);
        ol = append_bits(out, olen, ol, usx_hcodes[USX_ALPHA], usx_hcode_lens[USX_ALPHA]);
        state = USX_ALPHA;
      }
      ol = append_switch_code(out, olen, ol, state);
      ol = append_bits(out, olen, ol, usx_hcodes[USX_ALPHA], usx_hcode_lens[USX_ALPHA]);
      if (state == USX_DELTA) {
        state = USX_ALPHA;
        ol = append_switch_code(out, olen, ol, state);
        ol = append_bits(out, olen, ol, usx_hcodes[USX_ALPHA], usx_hcode_lens[USX_ALPHA]);
      }
    }
    c_next = 0;
    if (l+1 < len) { c_next = (is_str ? input.codeUnitAt(l + 1) : input[l + 1]); }

    if (c_in >= 32 && c_in <= 126) {
      if (is_upper && !is_all_upper) {
        for (ll=l+4; ll>=l && ll<len; ll--) {
          var c_u = (is_str ? input.codeUnitAt(ll) : input[ll]);
          if (c_u < 65 || c_u > 90){ break; }  // todo check
        }
        if (ll == l-1) {
          ol = append_switch_code(out, olen, ol, state);
          ol = append_bits(out, olen, ol, usx_hcodes[USX_ALPHA], usx_hcode_lens[USX_ALPHA]);
          state = USX_ALPHA;
          is_all_upper = true;
        }
      }
      if (state == USX_DELTA) {
        var ch_idx = " .,".indexOf(String.fromCharCode(c_in));
        if (ch_idx != -1) {
          ol = append_bits(out, olen, ol, UNI_STATE_SPL_CODE, UNI_STATE_SPL_CODE_LEN);
          ol = append_bits(out, olen, ol, usx_spl_code[ch_idx], usx_spl_code_len[ch_idx]);
          continue;  // todo check
        }
      }

      c_in -= 32;
      if (is_all_upper && is_upper){ c_in += 32; }
      if (c_in == 0) {
        if (state == USX_NUM){ ol = append_bits(out, olen, ol, usx_vcodes[NUM_SPC_CODE & 0x1F], usx_vcode_lens[NUM_SPC_CODE & 0x1F]); }
        else{ ol = append_bits(out, olen, ol, usx_vcodes[1], usx_vcode_lens[1]); }
      }
      else {
        c_in--;
        (ol, state) = append_code(out, olen, ol, usx_code_94[c_in], state, usx_hcodes, usx_hcode_lens);
      }
    }
    else if (c_in == 13 && c_next == 10) {
      (ol, state) = append_code(out, olen, ol, CRLF_CODE, state, usx_hcodes, usx_hcode_lens);
      l++;
    }
    else if (c_in == 10) {
      if (state == USX_DELTA) {
        ol = append_bits(out, olen, ol, UNI_STATE_SPL_CODE, UNI_STATE_SPL_CODE_LEN);
        ol = append_bits(out, olen, ol, 0xF0, 4);
      }
      else { (ol, state) = append_code(out, olen, ol, LF_CODE, state, usx_hcodes, usx_hcode_lens); }
    }
    else if (c_in == 13) { (ol, state) = append_code(out, olen, ol, CR_CODE, state, usx_hcodes, usx_hcode_lens); }
    else if (c_in == 9) { (ol, state) = append_code(out, olen, ol, TAB_CODE, state, usx_hcodes, usx_hcode_lens); }
    else {
      int uni, utf8len;
      (uni, utf8len) = readUTF8(input, len, l);
      if (uni > 0) {
        l += utf8len;
        if (state != USX_DELTA) {
          int uni2;
          (uni2, utf8len) = readUTF8(input, len, l);
          if (uni2 > 0) {
            if (state != USX_ALPHA) {
              ol = append_switch_code(out, olen, ol, state);
              ol = append_bits(out, olen, ol, usx_hcodes[USX_ALPHA], usx_hcode_lens[USX_ALPHA]);
            }
            ol = append_switch_code(out, olen, ol, state);
            ol = append_bits(out, olen, ol, usx_hcodes[USX_ALPHA], usx_hcode_lens[USX_ALPHA]);
            ol = append_bits(out, olen, ol, usx_vcodes[1], usx_vcode_lens[1]);
            state = USX_DELTA;
          } else {
            ol = append_switch_code(out, olen, ol, state);
            ol = append_bits(out, olen, ol, usx_hcodes[USX_DELTA], usx_hcode_lens[USX_DELTA]);
          }
        }
        ol = encodeUnicode(out, olen, ol, uni, prev_uni);
        prev_uni = uni;
        l--;
      }
      else {
        var bin_count = 1;
        for (var bi = l + 1; bi < len; bi++) {
          var c_bi = input[bi];
          if (readUTF8(input, len, bi) > 0){ break; }  // todo check
          if (bi < (len - 4) && c_bi == input[bi - 1] && c_bi == input[bi + 1] && c_bi == input[bi + 2] && c_bi == input[bi + 3]){ break; }  // todo check
          bin_count++;
        }
        ol = append_nibble_escape(out, olen, ol, state, usx_hcodes, usx_hcode_lens);
        ol = append_bits(out, olen, ol, 0xF8, 5);
        ol = encodeCount(out, olen, ol, bin_count);
        do { ol = append_bits(out, olen, ol, input[l++], 8); } while (--bin_count > 0);
        l--;
      }
    }
  }
  if (need_full_term_codes) {
    var orig_ol = ol;
    ol = append_final_bits(out, olen, ol, state, is_all_upper, usx_hcodes, usx_hcode_lens);
    return (ol / 8) * 4 + ((((ol-orig_ol)/8) as int) & 3);
  }
  else {
    var rst = (ol + 7) / 8 as int;
    ol = append_final_bits(out, rst, ol, state, is_all_upper, usx_hcodes, usx_hcode_lens);
    return rst;
  }
}

readBit(input, bit_no) {
  return input[bit_no >> 3] & (0x80 >> (bit_no % 8));
}

read8bitCode(input, len, bit_no) {
  var bit_pos = bit_no & 0x07;
  var char_pos = bit_no >> 3;
  len >>= 3;
  var code = (input[char_pos] << bit_pos) & 0xFF;
  char_pos++;
  if (char_pos < len) { code |= input[char_pos] >> (8 - bit_pos); }
  else { code |= (0xFF >> ((8 - bit_pos) as int)); }
  return (code, bit_no);
}

const SECTION_COUNT = 5;
final usx_vsections = Uint8List.fromList([0x7F, 0xBF, 0xDF, 0xEF, 0xFF]);
final usx_vsection_pos = Uint8List.fromList([0, 4, 8, 12, 20]);
final usx_vsection_mask = Uint8List.fromList([0x7F, 0x3F, 0x1F, 0x0F, 0x0F]);
final usx_vsection_shift = Uint8List.fromList([5, 4, 3, 1, 0]);

final usx_vcode_lookup = Uint8List.fromList([(1 << 5) + 0, (1 << 5) + 0, (2 << 5) + 1, (2 << 5) + 2, (3 << 5) + 3, (3 << 5) + 4, (3 << 5) + 5, (3 << 5) + 6, (3 << 5) + 7, (3 << 5) + 7, (4 << 5) + 8, (4 << 5) + 9, (5 << 5) + 10, (5 << 5) + 10, (5 << 5) + 11, (5 << 5) + 11, (5 << 5) + 12, (5 << 5) + 12, (6 << 5) + 13, (6 << 5) + 14, (6 << 5) + 15, (6 << 5) + 15, (6 << 5) + 16, (6 << 5) + 16, (6 << 5) + 17, (6 << 5) + 17, (7 << 5) + 18, (7 << 5) + 19, (7 << 5) + 20, (7 << 5) + 21, (7 << 5) + 22, (7 << 5) + 23, (7 << 5) + 24, (7 << 5) + 25, (7 << 5) + 26, (7 << 5) + 27]);

(int, int) readVCodeIdx(input, int len, int bit_no) {
  if (bit_no < len) {
    int code;
    (code, bit_no) = read8bitCode(input, len, bit_no);
    var i = 0;
    do {
      if (code <= usx_vsections[i]) {
        var vcode = usx_vcode_lookup[usx_vsection_pos[i] + ((code & usx_vsection_mask[i]) >> usx_vsection_shift[i])];
        bit_no += ((vcode >> 5) + 1);
        if (bit_no > len){ return (99, bit_no); }
        return (vcode & 0x1F, bit_no);
      }
    } while (++i < SECTION_COUNT);
  }
  return (99, bit_no);
}

final len_masks = Uint8List.fromList([0x80, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE, 0xFF]);
readHCodeIdx(input, len, bit_no, usx_hcodes, usx_hcode_lens) {
  if (!usx_hcode_lens[USX_ALPHA]){ return (USX_ALPHA, bit_no); }
  if (bit_no < len) {
    int code;
    (code, bit_no) = read8bitCode(input, len, bit_no);
    for (var code_pos = 0; code_pos < 5; code_pos++) {
      if (usx_hcode_lens[code_pos] > 0 && (code & len_masks[usx_hcode_lens[code_pos] - 1]) == usx_hcodes[code_pos]) {
        bit_no += usx_hcode_lens[code_pos];
        return (code_pos, bit_no);
      }
    }
  }
  return (99, bit_no);
}

getStepCodeIdx(input, int len, int bit_no, int limit) {
  var idx = 0;
  while (bit_no < len && readBit(input, bit_no) > 0) {
    idx++;
    bit_no++;
    if (idx == limit){ return (idx, bit_no); }
  }
  if (bit_no >= len){ return (99, bit_no); }
  bit_no++;
  return (idx, bit_no);
}

int getNumFromBits(input, int len, int bit_no, int count) {
  int ret = 0;
  while (count-- > 0 && bit_no < len) {
    ret += (readBit(input, bit_no) > 0 ? 1 << count : 0);
    bit_no++;
  }
  return count < 0 ? ret : -1;
}

readCount(input, bit_no, len) {
  int idx = 0;
  (idx, bit_no) = getStepCodeIdx(input, len, bit_no, 4);
  if (idx == 99){ return (-1, bit_no); }
  if (bit_no + count_bit_lens[idx] - 1 >= len){ return (-1, bit_no); }

  int count = getNumFromBits(input, len, bit_no, count_bit_lens[idx]) + (idx > 0 ? count_adder[idx - 1] : 0);
  bit_no += count_bit_lens[idx];
  return (count, bit_no);
}

readUnicode(input, int bit_no, int len) {
  int idx;
  (idx, bit_no) = getStepCodeIdx(input, len, bit_no, 5);
  if (idx == 99){ return (0x7FFFFF00 + 99, bit_no); }
  if (idx == 5) {
    (idx, bit_no) = getStepCodeIdx(input, len, bit_no, 4);
    return (0x7FFFFF00 + idx, bit_no);
  }
  if (idx >= 0) {
    var sign = (bit_no < len ? readBit(input, bit_no) : 0);
    bit_no++;
    if (bit_no + uni_bit_len[idx] - 1 >= len){ return (0x7FFFFF00 + 99, bit_no); }
    var count = getNumFromBits(input, len, bit_no, uni_bit_len[idx]);
    count += uni_adder[idx];
    bit_no += uni_bit_len[idx];
    return (sign > 0 ? -count : count, bit_no);
  }
  return (0, bit_no);
}

decodeRepeatArray(input, len, out_arr, out, bit_no, prev_lines_arr, prev_lines_idx, usx_hcodes, usx_hcode_lens, usx_freq_seq, usx_templates) {
  var dict_len = 0;
  (dict_len, bit_no) = readCount(input, bit_no, len);
  dict_len += NICE_LEN;
  if (dict_len < NICE_LEN){ return (-1, out); }

  int dist;
  (dist, bit_no) = readCount(input, bit_no, len);
  if (dist < 0){ return (-1, out); }

  int ctx;
  (ctx, bit_no) = readCount(input, bit_no, len);
  if (ctx < 0){ return (-1, out); }
  var line;
  if (ctx == 0){ line = (out_arr?? out); }
  else {
    if (prev_lines_idx < ctx){ return (-1, out); }
    if (out_arr == null) { line = unishox2_decompress(prev_lines_arr, prev_lines_idx - ctx, out_arr: null, usx_hcodes: usx_hcodes, usx_hcode_lens: usx_hcode_lens, usx_freq_seq: usx_freq_seq, usx_templates: usx_templates); }
    else {
      line = Uint8List((dist + dict_len) * 2);
      unishox2_decompress(prev_lines_arr, prev_lines_idx - ctx, out_arr: line, usx_hcodes: usx_hcodes, usx_hcode_lens: usx_hcode_lens, usx_freq_seq: usx_freq_seq, usx_templates: usx_templates);
    }
  }
  if (out_arr == null) { out += (line is String ? line.substring(dist, dict_len) : line.slice(dist, dict_len)); }
  else {
    for (var i = 0; i < dict_len; i++) {
      if (out >= out_arr.length){ break; }  // todo check
      out_arr[out] = line[dist + i];
      out++;
    }
  }
  return (bit_no, out);
}

decodeRepeat(input, int len, out_arr, out, int bit_no) {
  int dict_len;
  (dict_len, bit_no) = readCount(input, bit_no, len);
  dict_len += NICE_LEN;
  if (dict_len < NICE_LEN){ return (-1, out); }
  int dist;
  (dist, bit_no) = readCount(input, bit_no, len);
  dist += (NICE_LEN - 1);
  if (dist < NICE_LEN - 1){ return (-1, out); }
  if (out_arr == null) {
    if (out.length < dist){ return (-1, out); }
    out += out.substr(out.length - dist, dict_len);
  }
  else {
    for (var i = 0; i < dict_len; i++) {
      if (out >= out_arr.length){ break; }
      out_arr[out] = out_arr[out - dist];
      out++;
    }
  }
  return (bit_no, out);
}

getHexChar(int nibble, hex_type) {
  if (nibble >= 0 && nibble <= 9) { return String.fromCharCode(48 + nibble); }
  else if (hex_type < USX_NIB_HEX_UPPER) { return String.fromCharCode(97 + nibble - 10);}
  return String.fromCharCode(65 + nibble - 10);
}

writeUTF8(out_arr, out, int uni) {
  if (uni < (1 << 11)) {
    out_arr[out++] = (0xC0 + (uni >> 6));
    out_arr[out++] = (0x80 + (uni & 0x3F));
  }
  else if (uni < (1 << 16)) {
    out_arr[out++] = (0xE0 + (uni >> 12));
    out_arr[out++] = (0x80 + ((uni >> 6) & 0x3F));
    out_arr[out++] = (0x80 + (uni & 0x3F));
  } else {
    out_arr[out++] = (0xF0 + (uni >> 18));
    out_arr[out++] = (0x80 + ((uni >> 12) & 0x3F));
    out_arr[out++] = (0x80 + ((uni >> 6) & 0x3F));
    out_arr[out++] = (0x80 + (uni & 0x3F));
  }
  return out;
}

String appendChar(out_arr, out, String ch) {
  if (out_arr == null) { out += ch.codeUnitAt(0); }
  else {
    if (out < out_arr.length) { out_arr[out++] = ch.codeUnitAt(0); }
  }
  return out;
}

appendString(out_arr, out, str) {
  if (out_arr == null){ out += str; }
  else {
    for (var i = 0; i < str.length; i++) {
      if (out >= out_arr.length){ break; }  // todo check
      out_arr[out++] = str.codeUnitAt(i);
    }
  }
  return out;
}
unishox2_decompress(input, len, {out_arr, Uint8List? usx_hcodes, Uint8List? usx_hcode_lens, usx_freq_seq, usx_templates}) {
  usx_hcodes ??= USX_HCODES_DFLT;
  usx_hcode_lens ??= USX_HCODE_LENS_DFLT;
  usx_freq_seq ??= USX_FREQ_SEQ_DFLT;
  usx_templates ??= USX_TEMPLATES;


  int dstate;
  int bit_no;
  int h, v;
  bool is_all_upper;
  List<String>? prev_lines_arr;
  int prev_lines_idx;

  init_coder();
  bit_no = 1;
  dstate = h = USX_ALPHA;
  is_all_upper = false;
  int prev_uni = 0;

  prev_lines_idx = len;  // todo check
  if (input is List<String>) {
    prev_lines_arr = input;
    input = prev_lines_arr[prev_lines_idx];
    len = input.length;
  }

  len <<= 3;
  String out = (out_arr == null ? '' : '\u0000');
  while (bit_no < len) {
    var orig_bit_no = bit_no;
    if (dstate == USX_DELTA || h == USX_DELTA) {
      if (dstate != USX_DELTA){ h = dstate; }
      int delta;
      (delta, bit_no) = readUnicode(input, bit_no, len);
      if ((delta >> 8) == 0x7FFFFF) {
        var spl_code_idx = delta & 0x000000FF;
        if (spl_code_idx == 99){ break; }  // todo check
        switch (spl_code_idx) {
          case 0:
            out = appendChar(out_arr, out, ' ');
            continue;  // todo check
          case 1:
            (h, bit_no) = readHCodeIdx(input, len, bit_no, usx_hcodes, usx_hcode_lens);
            if (h == 99) {
              bit_no = len;
              continue;  // todo check
            }
            if (h == USX_DELTA || h == USX_ALPHA) {
              dstate = h;
              continue;  // todo check
            }
            if (h == USX_DICT) {
              if (prev_lines_arr == null){ (bit_no, out) = decodeRepeat(input, len, out_arr, out, bit_no); }
              else { (bit_no, out) = decodeRepeatArray(input, len, out_arr, out, bit_no, prev_lines_arr, prev_lines_idx, usx_hcodes, usx_hcode_lens, usx_freq_seq, usx_templates); }
              if (bit_no < 0){ return out; }
              h = dstate;
              continue;  // todo check
            }
            break;  // todo check
          case 2:
            out = appendChar(out_arr, out, ',');
            continue;  // todo check
          case 3:
            out = appendChar(out_arr, out, '.');
            continue;  // todo check
          case 4:
            out = appendChar(out_arr, out, String.fromCharCode(10));
            continue;  // todo check
        }
      }
      else {
        prev_uni += delta;
        if (prev_uni > 0) {
          if (out_arr == null){ out += String.fromCharCode(prev_uni); }
          else{ out = writeUTF8(out_arr, out, prev_uni); }
        }
      }
      if (dstate == USX_DELTA && h == USX_DELTA){ continue; }  // todo check
    }
    else{ h = dstate; }
    var c = "";
    bool is_upper = is_all_upper;
    (v, bit_no) = readVCodeIdx(input, len, bit_no);
    if (v == 99 || h == 99) {
      bit_no = orig_bit_no;
      break;  // todo check
    }
    if (v == 0 && h != USX_SYM) {
      if (bit_no >= len){ break; }
      if (h != USX_NUM || dstate != USX_DELTA) {
        (h, bit_no) = readHCodeIdx(input, len, bit_no, usx_hcodes, usx_hcode_lens);
        if (h == 99 || bit_no >= len) {
          bit_no = orig_bit_no;
          break;  // todo check
        }
      }
      if (h == USX_ALPHA) {
        if (dstate == USX_ALPHA) {
          if (usx_hcode_lens[USX_ALPHA] == 0 && TERM_BYTE_PRESET_1 == (read8bitCode(input, len, bit_no - SW_CODE_LEN) & (0xFF << (8 - (is_all_upper ? TERM_BYTE_PRESET_1_LEN_UPPER : TERM_BYTE_PRESET_1_LEN_LOWER))))) { break; }  // todo check
          if (is_all_upper) {
            is_upper = is_all_upper = false;
            continue;  // todo check
          }
          (v, bit_no) = readVCodeIdx(input, len, bit_no);
          if (v == 99) {
            bit_no = orig_bit_no;
            break;  // todo check
          }
          if (v == 0) {
            (h, bit_no) = readHCodeIdx(input, len, bit_no, usx_hcodes, usx_hcode_lens);
            if (h == 99) {
              bit_no = orig_bit_no;
              break;  // todo check
            }
            if (h == USX_ALPHA) {
              is_all_upper = true;
              continue;  // todo check
            }
          }
          is_upper = true;
        }
        else {
          dstate = USX_ALPHA;
          continue;  // todo check
        }
      }
      else if (h == USX_DICT) {
        if (prev_lines_arr == null){ (bit_no, out) = decodeRepeat(input, len, out_arr, out, bit_no); }
        else {
          (bit_no, out) = decodeRepeatArray(input, len, out_arr, out, bit_no,
              prev_lines_arr, prev_lines_idx, usx_hcodes, usx_hcode_lens, usx_freq_seq, usx_templates);
        }
        if (bit_no < 0){ break; }  // todo check
        continue;  // todo check
      }
      else if (h == USX_DELTA) { continue; }  // todo check
      else {
        if (h != USX_NUM || dstate != USX_DELTA){ (v, bit_no) = readVCodeIdx(input, len, bit_no); }
        if (v == 99) {
          bit_no = orig_bit_no;
          break;  // todo check
        }
        if (h == USX_NUM && v == 0) {
          int idx;
          (idx, bit_no) = getStepCodeIdx(input, len, bit_no, 5);
          switch (idx){
            case 99:
              break;  // todo check
            case 0:
              (idx, bit_no) = getStepCodeIdx(input, len, bit_no, 4);
              if (idx >= 5){ break; }  // todo check
              int rem;
              (rem, bit_no) = readCount(input, bit_no, len);
              if (rem < 0){ break; }  // todo check
              if (usx_templates == null || usx_templates[idx] == null){ break; }  // todo check

              var tlen = usx_templates[idx].length;
              if (rem > tlen){ break; }  // todo check
              rem = tlen - rem;
              bool eof = false;
              for (int j = 0; j < rem; j++) {
                var c_t = usx_templates[idx][j];
                if (c_t == 'f' || c_t == 'r' || c_t == 't' || c_t == 'o' || c_t == 'F') {
                  var nibble_len = (c_t == 'f' || c_t == 'F' ? 4 : (c_t == 'r' ? 3 : (c_t == 't' ? 2 : 1)));
                  var raw_char = getNumFromBits(input, len, bit_no, nibble_len);
                  if (raw_char < 0) {
                    eof = true;
                    break;  // todo check
                  }
                  var nibble_char = getHexChar(raw_char, c_t == 'f' ? USX_NIB_HEX_LOWER : USX_NIB_HEX_UPPER);
                  out = appendChar(out_arr, out, nibble_char);
                  bit_no += nibble_len;
                }
                else { out = appendChar(out_arr, out, c_t); }
              }
              if (eof) break;  // todo check
              break;
            case 5:
              int bin_count;
              (bin_count, bit_no) = readCount(input, bit_no, len);
              if (bin_count < 0) { break; }  // todo check
              if (bin_count == 0) { break; }  // todo check
              do {
                var raw_char = getNumFromBits(input, len, bit_no, 8);
                if (raw_char < 0) { break; }  // todo check
                var bin_byte = String.fromCharCode(raw_char);
                out = appendChar(out_arr, out, bin_byte);
                bit_no += 8;
              } while (--bin_count > 0);
              break;  // todo check
            default:
              var nibble_count = 0;
              if (idx == 2 || idx == 4){ nibble_count = 32; }
              else {
                (nibble_count, bit_no) = readCount(input, bit_no, len);
                if (nibble_count < 0){ break; }  // todo check
                if (nibble_count == 0) { break; }  // todo check
              }
              do {
                var nibble = getNumFromBits(input, len, bit_no, 4);
                if (nibble < 0) { break; }  // todo check
                var nibble_char = getHexChar(nibble, idx < 3 ? USX_NIB_HEX_LOWER : USX_NIB_HEX_UPPER);
                out = appendChar(out_arr, out, nibble_char);
                if ((idx == 2 || idx == 4) && (nibble_count == 25 || nibble_count == 21 || nibble_count == 17 || nibble_count == 13)){
                  out = appendChar(out_arr, out, '-');
                }
                bit_no += 4;
              } while (--nibble_count > 0);
              if (nibble_count > 0) break;  // todo check
          }
          if (dstate == USX_DELTA) { h = USX_DELTA; }
          continue;  // todo check
        }
      }
    }
    if (is_upper && v == 1) {
      continue;  // todo check
    }
    if (h < 3 && v < 28) { c = String.fromCharCode(usx_sets[h][v]); }
    if (c.codeUnitAt(0) >= 'a'.codeUnitAt(0) && c.codeUnitAt(0) <= 'z'.codeUnitAt(0)) {
      dstate = USX_ALPHA;
      if (is_upper) { c = String.fromCharCode(c.codeUnitAt(0)-32); }
    }
    else {
      if (c != '\u0000' && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) { dstate = USX_NUM; }
      else if (c.codeUnitAt(0) == 0 && c != '0') {
        if (v == 8) { out = appendString(out_arr, out, "\r\n"); }
        else if (h == USX_NUM && v == 26) {
          int count;
          (count, bit_no) = readCount(input, bit_no, len);
          if (count < 0){ break; }  // todo check
          count += 4;
          var rpt_c = (out_arr == null ? out[out.length - 1] : String.fromCharCode(out_arr[(out as int) - 1]));  // todo check
          for(; count > 0; count--){ out = appendChar(out_arr, out, rpt_c); }
        }
        else if (h == USX_SYM && v > 24) {
          v -= 25;
          out = appendString(out_arr, out, usx_freq_seq[v]);
        }
        else if (h == USX_NUM && v > 22 && v < 26) {
          v -= (23 - 3);
          out = appendString(out_arr, out, usx_freq_seq[v]);
        }
        else { break; }  // todo check
        if (dstate == USX_DELTA){ h = USX_DELTA; }
        continue;  // todo check
      }
    }
    if (dstate == USX_DELTA){ h = USX_DELTA; }
    out = appendChar(out_arr, out, c);
  }
  return out;
}
