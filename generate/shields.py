#!/usr/bin/env python3

# Generate highway shields as SVG files in symbols/shields.

from __future__ import print_function
import copy, lxml.etree, math, os

def main():
    namespace = 'http://www.w3.org/2000/svg'
    svgns = '{' + namespace + '}'
    svgnsmap = {None: namespace}

    config = {}
    config['base'] = {}

    # font_height and font_width are determined by trial and error
    config['base']['rounded_corners'] = 1
    config['base']['font_height'] = 7
    config['base']['font_width'] = 3.5
    config['base']['padding_x'] = 2
    config['base']['padding_y'] = 1
    config['base']['stroke_width'] = 1

    # Fall back colours used if no colours are defined for a road type.
    config['base']['fill'] = '#f1f1f1'
    config['base']['stroke_fill'] = '#c6c6c6'

    config['global'] = {}

    config['global']['types'] = ['motorway', 'trunk', 'primary', 'secondary', 'tertiary']
    config['global']['max_width'] = 11
    config['global']['max_height'] = 4
    config['global']['output_dir'] = 'symbols/shields/' # specified relative to the script location

    config['global']['additional_sizes'] = ['base']

    # specific values overwrite config['base'] ones
    config['motorway'] = {
        'fill': 'rgb(204, 204, 204)',
        'stroke_fill': 'rgb(120, 120, 120)',
    }
    config['trunk'] = {
        'fill': 'rgb(204, 204, 204)',
        'stroke_fill': 'rgb(120, 120, 120)',
    }
    config['primary'] = {
        'fill': 'rgb(242, 225, 176)',
        'stroke_fill': 'rgb(219, 170, 35)',
    }
    config['secondary'] = {
        'fill': 'rgb(248, 248, 160)',
        'stroke_fill': 'rgb(191, 191, 13)',
    }
    config['tertiary'] = {
        'fill': 'rgb(255, 255, 255)',
        'stroke_fill': 'rgb(200, 200, 200)',
    }

    if not os.path.exists(os.path.dirname(config['global']['output_dir'])):
        os.makedirs(os.path.dirname(config['global']['output_dir']))

    for height in range(1, config['global']['max_height'] + 1):
        for width in range(1, config['global']['max_width'] + 1):
            for shield_type in config['global']['types']:

                # merge base config and specific styles
                vars = copy.deepcopy(config['base'])
                if shield_type in config:
                    for option in config[shield_type]:
                        vars[option] = config[shield_type][option]

                for shield_size in config['global']['additional_sizes']:

                    if shield_size != 'base':
                        if shield_size in config:
                            for option in config[shield_size]:
                                vars[option] = config[shield_size][option]

                    shield_width = 2 * vars['padding_x'] + math.ceil(vars['font_width'] * width)
                    shield_height = 2 * vars['padding_y'] + math.ceil(vars['font_height'] * height)

                    svg = lxml.etree.Element('svg', nsmap=svgnsmap)
                    svg.set('width', '100%')
                    svg.set('height', '100%')
                    svg.set('viewBox', '0 0 ' + str(shield_width    + vars['stroke_width']) + ' ' + str(shield_height + vars['stroke_width']))

                    if vars['stroke_width'] > 0:
                        offset_x = vars['stroke_width'] / 2.0
                        offset_y = vars['stroke_width'] / 2.0
                    else:
                        offset_x = 0
                        offset_y = 0

                    shield = lxml.etree.Element(svgns + 'rect')
                    shield.set('x', str(offset_x))
                    shield.set('y', str(offset_y))
                    shield.set('width', str(shield_width))
                    shield.set('height', str(shield_height))
                    if vars['rounded_corners'] > 0:
                        shield.set('rx', str(vars['rounded_corners']))
                        shield.set('ry', str(vars['rounded_corners']))
                    shield.set('id', 'shield')

                    stroke = ''
                    if vars['stroke_width'] > 0:
                        stroke = 'stroke:' + vars['stroke_fill'] + ';stroke-width:' + str(vars['stroke_width']) + ';'

                    shield.set('style', 'fill:' + vars['fill'] + ';' + stroke)

                    svg.append(shield)

                    filename = shield_type + '_' + str(width) + 'x' + str(height)
                    if shield_size != 'base':
                        filename = filename + '_' + shield_size

                    filename = filename + '.svg'

                    # save file
                    try:
                        with open(os.path.join(os.path.dirname(__file__), config['global']['output_dir'] + filename), 'w') as shieldfile:
                            shieldfile.write(lxml.etree.tostring(svg, encoding='utf-8', xml_declaration=True, pretty_print=True).decode('utf-8'))
                    except IOError:
                        print('Could not save file ' + filename + '.')
                        continue

if __name__ == "__main__":
    main()