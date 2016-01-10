require 'set'
require 'sketchup'
class Slicer
    def initialize
        #@_XXX =
        @ground = [Geom::Point3d.new(0,0,0), Geom::Vector3d.new(0,0,1)]
        @zaxis = Geom::Vector3d.new 0,0,1 
    end
    def findOuterWallFaces(entities)
        
    end
    def findOuterFaces(faces)
        wallFaces = Set.new
        floorFaces = Set.new
        otherFaces = Set.new
        faces.each { |face|
            edgeParallelToZAxis = 0
            face.outer_loop.edges.each {|edge|
                if edge.line[1].parallel?(@zaxis)
                    edgeParallelToZAxis = edgeParallelToZAxis+1
                end
            }
            if Geom.intersect_plane_plane(face.plane,@ground)==nil
                floorFaces.add(face)
            else
                if edgeParallelToZAxis == 2
                    wallFaces.add(face)
                else
                    otherFaces.add(face)
                end
            end
        }
        return wallFaces, floorFaces, otherFaces
    end
    def findBiggestFloorFace(floorFaces) 
        biggestFloorFace = nil
        groundLevel = nil
        floorFaces.each {|face|
            if biggestFloorFace==nil
                biggestFloorFace = face
            else
                if face.area>biggestFloorFace.area
                    biggestFloorFace = face
                end
#                groundLevel = biggestFloorFace.outer_loop.vertices[0].position.z
#                face.outer_loop.vertices.each {|v|
#                    pt = Geom::Point3d.new(v.position.x, v.position.y, groundLevel)
#                    if Geom.point_in_polygon_2D(pt, biggestFloorFace.outer_loop.vertices, true)
#                    else
#                        biggestFloorFace = face
#                    end
#                }
            end
        }
        return biggestFloorFace
    end
    def removeFingerSpace(entities, face, materialThickness, fingerWidth, invert, collector)
         #Take vertices or edges.start/edges.end ?
         #eu = Set.new(face.outer_loop.edgeuses)
         eu = face.outer_loop.edgeuses.collect { |edgeUse| [edgeUse.start_vertex_normal,edgeUse.edge.start.position,edgeUse.edge.end.position,edgeUse.edge.length]}
         #face.outer_loop.edgeuses.each { |edgeUse }
         validPoints = Set.new([Sketchup::Face::PointInside, Sketchup::Face::PointOnVertex, Sketchup::Face::PointOnEdge])
         #gb = groupBounds.min.to_a
         #gb = gb + gb
         eu.each { |start_vertex_normal,start,zend,length|
            #
            myid = (start < zend ? start.to_a+zend.to_a : zend.to_a+start.to_a).to_s 
            
            #myid="zzz"
            reverse = collector.include?(myid) ? 1 : 0
            puts myid.to_s
            #puts groupTransform.to_a.to_s
            puts reverse
            #reverse = 0
            collector.push(myid)
            #edge = edge
            #start = edge.start.position
            #zend = edge.end.position
            vector = (zend - start).normalize
            #length = edge.length
            halfLength = length / 2
            perpendicular = start_vertex_normal * vector
            perpendicular.length = perpendicular.length * materialThickness
            fingerVector = vector.clone()
            fingerVector.length = fingerVector.length * fingerWidth
            for p in 0..(halfLength/fingerWidth)-1
                if p % 2 == reverse
                    for w in 0..1
                        v = vector.clone()
                        #v.length = v.length * fingerWidth * p * 2 * (0.5-w) - w*v.length*fingerWidth
                        v.length = v.length*fingerWidth * (p*2*(0.5-w) - w)
                        t = Geom::Transformation.translation(v)
                        pt1 = (w==0 ? start : zend).transform(t)
                        tWidth = Geom::Transformation.translation(fingerVector)
                        tPerp = Geom::Transformation.translation(perpendicular)
                        
                        pt2 = pt1.transform(tPerp)
                        entities.add_cpoint w==0 ? pt1 : pt2
                        pt3 = pt2.transform(tWidth)
                        pt4 = pt1.transform(tWidth)
                        
                        #TODO : check if each point are in original face, otherwise don't do that !!!
                        #if [pt1, pt2, pt3, pt4].none? {|pt| validPoints.include?(face.classify_point(pt)==Sketchup::Face::PointInside)}
                            e1 = entities.add_edges(pt1,  pt2)
                            e2 = entities.add_edges(pt2,  pt3)
                            e3 = entities.add_edges(pt3,  pt4)
                            e1[0].find_faces
                            e2[0].find_faces
                            e3[0].find_faces
                            e4 = entities.add_edges(pt4, pt1)
                            entities.erase_entities e4
                        #end
                        
                        
                        #edges = entities.add_edges(pt1, pt1.transform(tPerp), pt1.transform(tPerp).transform(tWidth), pt1.transform(tWidth), pt1)
                        #edges.each {|e| e.find_faces}
                        #edge.find_faces
                        
                        #entities.erase_entities edges
                        #entities.outer_loop.edgeuses.start_vertex_normal
                    end
                end
            end
         }
    end
    def slice(entities)
        #findOuterFaces(entities)
        
        #zaxis = Sketchup.active_model.axes[2]
        mainGroup = entities.add_group.entities
        faces = Set.new(entities.grep(Sketchup::Face))
        collector = Array.new()
        wallFaces, floorFaces, otherFaces = findOuterFaces(faces)
        biggestFloorFace = findBiggestFloorFace(floorFaces)
        if biggestFloorFace == nil
        else
            #group = mainGroup.add_group
            #newface = group.entities.add_face(biggestFloorFace.outer_loop.vertices)
            #removeFingerSpace(group.entities, newface, 0.006.m, 0.020.m, false, collector)
            # Search every faces that intersects with biggestFloorFace
            #
            
            faces.each {|face|
                group = mainGroup.add_group
                gents = group.entities
                newface = gents.add_face(face.outer_loop.vertices)
                face.loops.each { |zloop|
                    if zloop.outer?
                    else
                        fFace = gents.add_face(zloop.vertices)
                        gents.erase_entities(fFace)
                    end
                }
                removeFingerSpace(gents, newface, 0.006.m, 0.020.m, false, collector)
            }
            
#            biggestFloorFace.edges.each {|edge|
#                edge.faces.each { |face|
#                    if floorFaces.include?(face)
#                    else
#                    end
#                }
#            }
            #biggestFloorFace
        end
        collector.sort!
        collector.each { |elt| 
            puts elt
        }
=begin
        group = entities.add_group
        wallFaces.each {|face|
            group.entities.add_face(face.outer_loop.vertices)
        }
        group = entities.add_group
        floorFaces.each {|face|
            group.entities.add_face(face.outer_loop.vertices)
        }
        group = entities.add_group
        otherFaces.each {|face|
            group.entities.add_face(face.outer_loop.vertices)
        }
=end

        #clone face : entities.add_instance(face, IDENTITY)
        
        #make groups of each walls of contiguous face
        #Simplified versions :
        #Walls are all faces with 2 edges // Z
        #Floor are all face // with Face Z=0
        #Others are roof
        #faces.each {|face| }
    end
end

pluginsMenu = UI::menu("Plugins")
item = pluginsMenu.add_item("Slice me for laser cutting please !") {
    model = Sketchup.active_model()
    slicer = Slicer.new
    slicer.slice(model.active_entities)
}