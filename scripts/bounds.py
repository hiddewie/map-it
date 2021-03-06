#!/usr/bin/env python
# -*- coding: utf-8 -*-
import math
import re

import mapnik

import environment

EPSG_4326 = mapnik.Projection('+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs')
EPSG_3857 = mapnik.Projection('+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +no_defs +over')
latitudeLongitudeToWebMercator = mapnik.ProjTransform(EPSG_4326, EPSG_3857)

ORIENTATION_LANDSCAPE = 'landscape'
ORIENTATION_PORTRAIT = 'portrait'


def determinePaperDimensions(paperSize):
    # Paper sizes in meter
    paperSizes = {
        'A5': {'width': 0.149, 'height': 0.210},
        'A4': {'width': 0.210, 'height': 0.297},
        'A3': {'width': 0.297, 'height': 0.420},
        'A2': {'width': 0.420, 'height': 0.594},
        'A1': {'width': 0.594, 'height': 0.841},
        'A0': {'width': 0.841, 'height': 1.189},
    }

    millimeters = re.match(r'^(\d+\.?\d*) mm [x×] (\d+\.?\d*) mm$', paperSize)
    meters = re.match(r'^(\d+\.?\d*) m [x×] (\d+\.?\d*) m$', paperSize)
    inches = re.match(r'^(\d+\.?\d*) in [x×] (\d+\.?\d*) in$', paperSize)
    if paperSize in paperSizes:
        return paperSizes[paperSize]['width'], paperSizes[paperSize]['height']
    elif millimeters:
        return float(millimeters.group(1)) / 1000, float(millimeters.group(2)) / 1000
    elif meters:
        return float(meters.group(1)), float(meters.group(2))
    elif inches:
        return float(inches.group(1)) * 0.0254, float(inches.group(2)) * 0.0254
    else:
        environment.exitError("The paper size should be one of the values %s or of the form `A mm x B mm`, `A m x B m` or `A in x B in`, but %s was given" % (list(paperSizes.keys()), paperSize))
        return


def determineOrientation(orientation):
    paperOrientations = {
        ORIENTATION_LANDSCAPE,
        ORIENTATION_PORTRAIT,
    }
    if orientation not in paperOrientations:
        environment.exitError("The paper orientation should be one of the values %s but %s was given" % (paperOrientations, orientation))
        return

    return orientation


def rotatePaper(bounds, orientation):
    width, height = bounds
    if orientation == ORIENTATION_LANDSCAPE:
        width, height = height, width

    return width, height


def determineBoundingBox(bbox):
    bboxMatch = re.match(r'^(\d+\.?\d*):(\d+\.?\d*):(\d+\.?\d*):(\d+\.?\d*)$', bbox)

    if not bboxMatch:
        environment.exitError("The bounding box must be of the form A:B:C:D with (A, B) the bottom left corner and (C, D) the top right corner. %s was given" % (bbox,))
        return

    return latitudeLongitudeToWebMercator.forward(mapnik.Box2d(
        float(bboxMatch.group(1)),
        float(bboxMatch.group(2)),
        float(bboxMatch.group(3)),
        float(bboxMatch.group(4)),
    ))


def determinePageOverlap(overlap):
    pageOverlapMatch = re.match(r'^(\d+\.?\d*)%$', overlap)

    if not pageOverlapMatch:
        environment.exitError("The page overlap must be a percentage value, like '5%%' or '10.1%%'. %s was given" % (overlap,))
        return

    return float(overlap[:-1]) / 100.0


def determineScale(scale):
    if not scale.strip().startswith('1:'):
        environment.exitError("The scale should be of the form 1:N but %s was given" % (scale,))
        return
    try:
        return float(scale[2:])
    except:
        environment.exitError("The scale should parsable as a floating point number but got %s" % (scale[2:],))
        return


def boundingBoxes(bbox, pageOverlap, scale, paperDimensions):
    paperWidth, paperHeight = paperDimensions
    # A 'data' pixel is 1 meter (in UTM projection)
    pageWidth = paperWidth * scale
    pageHeight = paperHeight * scale

    # If the bounding box fits on one page, then do not use padding
    epsilon = 1
    fitsOnOnePageHorizontal = (bbox.maxx - bbox.minx) <= pageWidth + epsilon
    fitsOnOnePageVertical = (bbox.maxy - bbox.miny) <= pageHeight + epsilon

    numPagesHorizontal = 1 if fitsOnOnePageHorizontal else 1 + int(math.ceil(((bbox.maxx - bbox.minx) - pageWidth) / ((1.0 - pageOverlap) * pageWidth)))
    numPagesVertical = 1 if fitsOnOnePageVertical else 1 + int(math.ceil(((bbox.maxy - bbox.miny) - pageHeight) / ((1.0 - pageOverlap) * pageHeight)))

    # Fit the generated pages perfectly 'around' the bounding box
    paddingX = ((numPagesHorizontal * pageWidth - (numPagesHorizontal - 1) * pageOverlap * pageWidth) - (bbox.maxx - bbox.minx)) / 2
    paddingY = ((numPagesVertical * pageHeight - (numPagesVertical - 1) * pageOverlap * pageHeight) - (bbox.maxy - bbox.miny)) / 2

    boundingBoxes = []
    for i in range(numPagesHorizontal):
        for j in range(numPagesVertical):
            topLeft = int(bbox.minx - paddingX + i * pageWidth - i * pageOverlap * pageWidth), \
                      int(bbox.maxy + paddingY - j * pageHeight + j * pageOverlap * pageHeight)
            bottomRight = int(topLeft[0] + pageWidth), \
                          int(topLeft[1] - pageHeight)

            tileBoundingBox = latitudeLongitudeToWebMercator.backward(mapnik.Box2d(
                topLeft[0],
                topLeft[1],
                bottomRight[0],
                bottomRight[1],
            ))
            boundingBoxes.append(tileBoundingBox)

    return boundingBoxes


def mapDimensions(dimensions):
    width, height = dimensions
    print('Rendering map with page width paper size (%s m × %s m)' % (width, height))

    # Dots per inch (1 point = 1/72 inch, see https://pycairo.readthedocs.io/en/latest/reference/surfaces.html#class-pdfsurface-surface)
    dpi = 72
    # Dots per m
    dpm = dpi * 100 / 2.54

    mapWidth = int(width * dpm)
    mapHeight = int(height * dpm)

    return mapWidth, mapHeight


if __name__ == '__main__':
    boundingBox = determineBoundingBox(environment.require('BBOX'))
    pageOverlap = determinePageOverlap(environment.env('PAGE_OVERLAP', '5%'))
    # Default 1 cm on the map is 1.5 km in the world
    scale = determineScale(environment.env('SCALE', '1:150000'))
    paperWidth, paperHeight = determinePaperDimensions(environment.env('PAPER_SIZE', 'A4'))
    orientation = determineOrientation(environment.env('PAPER_ORIENTATION', ORIENTATION_PORTRAIT))
    printPaperWidth, printPaperHeight = rotatePaper((paperWidth, paperHeight), orientation)

    for bbox in boundingBoxes(boundingBox, pageOverlap, scale, (printPaperWidth, printPaperHeight)):
        print('%s:%s:%s:%s' % (bbox.minx, bbox.miny, bbox.maxx, bbox.maxy))
