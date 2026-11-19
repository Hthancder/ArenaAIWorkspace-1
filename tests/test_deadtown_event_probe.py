import unittest
import xml.etree.ElementTree as ET

from tools.deadtown_event_probe import UnsupportedAction, translate_actions


def action(action_id, args=(), who='self', relative='0', isnot='0'):
    node = ET.Element('action')
    for key, value in [('id', action_id), ('whoName', who), ('relative', relative), ('isnot', isnot)]:
        ET.SubElement(node, key).text = value
    arguments = ET.SubElement(node, 'arguments')
    for value in args:
        ET.SubElement(ET.SubElement(arguments, 'argument'), 'string').text = value
    return node


class EventTranslationTests(unittest.TestCase):
    def test_sequential_code_and_alarm(self):
        text = translate_actions([action('603', ['x = 1 // comment']), action('301', ['room_speed * 2', '3'])])
        self.assertIn('x = 1 // comment\n}', text)
        self.assertIn('alarm[3] = (room_speed * 2);', text)

    def test_condition_block_else_and_following_action(self):
        actions = [action('612', ['pause', '0', '0'], isnot='-1'), action('422'),
                   action('603', ['x = 1']), action('424'), action('421'),
                   action('422'), action('603', ['x = 2']), action('424'), action('603', ['x = 3'])]
        text = translate_actions(actions)
        self.assertIn('if (!(((pause) == (0))))', text)
        self.assertIn('else\n{', text)
        self.assertTrue(text.index('x = 1') < text.index('else') < text.index('x = 2') < text.index('x = 3'))

    def test_code_action_comment_ends_before_next_action(self):
        text = translate_actions([action('603', ['x = "/*"; /* disabled']), action('603', ['y = 2'])])
        self.assertIn('/* disabled\n*/\n', text)
        self.assertTrue(text.index('*/') < text.index('y = 2'))
        text = translate_actions([action('603', ['x = 1 // /* not a block'])])
        self.assertNotIn('*/', text)

    def test_nested_if_and_expression(self):
        text = translate_actions([action('408', ['x > 0']), action('408', ['y > 0']), action('603', ['x = y'])])
        self.assertIn('if ((x > 0))', text)
        self.assertIn('if ((y > 0))', text)

    def test_fails_closed(self):
        invalid = [[action('999')], [action('422')], [action('424')], [action('421')],
                   [action('301', ['3', '99'])], [action('603', ['x=1'], who='other')],
                   [action('612', ['x', '1', '2']), action('603', ['x=1'])],
                   [action('408', ['x'])]]
        for actions in invalid:
            with self.subTest(actions=actions):
                with self.assertRaises(UnsupportedAction):
                    translate_actions(actions)


if __name__ == '__main__':
    unittest.main()
